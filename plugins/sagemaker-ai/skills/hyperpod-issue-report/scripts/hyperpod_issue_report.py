#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# dependencies = [
#   "boto3>=1.26.0",
#   "botocore>=1.29.0",
#   "pexpect>=4.8.0",
# ]
# ///
"""
HyperPod Issue Report Collector

Collects diagnostic logs and configurations from multiple HyperPod nodes.
Supports both HyperPod EKS and HyperPod Slurm clusters.
Uses hyperpod_run_on_multi_nodes mechanism to execute collection scripts on nodes.
Downloads collection script from S3 and uploads results back to S3.
"""

import argparse
import boto3
import json
import os
import platform
import pexpect
import shlex
import shutil
import signal
import subprocess  # nosec B404 - required for kubectl CLI commands  # nosemgrep: gitlab.bandit.B404
import sys
import tarfile
import tempfile
import time
import traceback
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import List, Dict, Optional


# ============================================================================
# TIMEOUT CONFIGURATION
# ============================================================================
# These timeouts are calibrated for large clusters (tested up to 130 nodes).
# Adjust these values if you experience timeouts with larger clusters.
#
# Test results (130-node cluster):
# - kubectl commands: 1-26s (longest: kubectl describe pods)
# - SSM node collection: 31-48s per node
# ============================================================================

# SSM session timeouts (seconds)
# These are passed explicitly to each pexpect expect() call
SSM_SCRIPT_EXECUTION_TIMEOUT = 900  # 15 minutes - script execution on nodes
SSM_PROMPT_TIMEOUT = 60             # 60 seconds - prompt detection and setup

# kubectl command timeout (seconds)
KUBECTL_TIMEOUT = 600               # 10 minutes - all kubectl operations


class HyperPodIssueReportCollector:
    def __init__(self, cluster_name: str, s3_path: str, region: Optional[str] = None, debug: bool = False):
        self.cluster_name = cluster_name
        self.debug = debug

        # Parse S3 path
        self.s3_bucket, self.s3_prefix = self.parse_s3_path(s3_path)
        
        # Configure boto3 clients with optional region
        client_kwargs = {}
        if region:
            client_kwargs['region_name'] = region
        
        self.sagemaker_client = boto3.client('sagemaker', **client_kwargs)
        self.s3_client = boto3.client('s3', **client_kwargs)
        self.eks_client = boto3.client('eks', **client_kwargs)
        self.region = region
        
        self.cluster_arn = None
        self.cluster_id = None
        self.cluster_type = None  # 'eks' or 'slurm'
        self.eks_cluster_arn = None
        self.eks_cluster_name = None
        self.nodes = []
        
        # Generate unique report ID using UTC time
        self.report_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        self.report_s3_key = f"{self.s3_prefix}/{cluster_name}/{self.report_id}"
    
    def parse_s3_path(self, s3_path: str) -> tuple:
        """Parse S3 path into bucket and prefix.
        
        Accepts formats:
        - s3://bucket-name/prefix/path
        - s3://bucket-name
        """
        s3_path = s3_path.strip()
        
        # Require s3:// prefix
        if not s3_path.startswith('s3://'):
            raise ValueError(
                f"S3 path must start with 's3://' prefix.\n"
                f"Received: {s3_path}\n"
                f"Expected format: s3://bucket-name or s3://bucket-name/custom-prefix"
            )
        
        # Remove s3:// prefix
        s3_path = s3_path[5:]
        
        # Split into bucket and prefix
        parts = s3_path.split('/', 1)
        bucket = parts[0]
        prefix = parts[1].rstrip('/') if len(parts) > 1 else 'hyperpod-issue-reports'
        
        return bucket, prefix
    
    def extract_cluster_id_from_arn(self, cluster_arn: str) -> str:
        """Extract cluster ID from cluster ARN."""
        if cluster_arn:
            if '/cluster/' in cluster_arn:
                return cluster_arn.split('/cluster/')[-1]
            elif ':cluster/' in cluster_arn:
                return cluster_arn.split(':cluster/')[-1]
            parts = cluster_arn.split(':')
            return parts[-1]
        return None
    
    def get_slurm_node_name(self, instance_id: str) -> Optional[str]:
        """Get Slurm node name (e.g. ip-10-1-104-161) for a node via describe_cluster_node API."""
        try:
            response = self.sagemaker_client.describe_cluster_node(
                ClusterName=self.cluster_name,
                NodeId=instance_id
            )
            
            # Extract private DNS name from NodeDetails
            node_details = response.get('NodeDetails', {})
            private_dns = node_details.get('PrivateDnsHostname', '')
            
            # Private DNS format is like: ip-10-1-104-161.us-west-2.compute.internal
            # Extract the IP part (ip-10-1-104-161)
            if private_dns and private_dns.startswith('ip-'):
                # Get the first part before the first dot
                slurm_node_name = private_dns.split('.')[0]
                return slurm_node_name
            
            return None
            
        except Exception as e:
            print(f"Warning: Could not get Slurm node name for {instance_id}: {e}")
            if self.debug:
                traceback.print_exc()
            return None
    
    def get_cluster_nodes(self) -> List[Dict]:
        """Get all nodes in the HyperPod cluster and detect cluster type."""
        try:
            print(f"Describing cluster: {self.cluster_name}")
            response = self.sagemaker_client.describe_cluster(ClusterName=self.cluster_name)
            
            print(f"Cluster status: {response.get('ClusterStatus', 'Unknown')}")
            
            # Detect cluster type from Orchestrator field
            orchestrator = response.get('Orchestrator', {})
            
            if 'Eks' in orchestrator:
                self.cluster_type = 'eks'
                print(f"Detected cluster type: EKS")
                # Extract EKS cluster ARN
                eks_config = orchestrator.get('Eks', {})
                self.eks_cluster_arn = eks_config.get('ClusterArn')
                if self.eks_cluster_arn:
                    # Extract cluster name from ARN: arn:aws:eks:region:account:cluster/cluster-name
                    self.eks_cluster_name = self.eks_cluster_arn.split('/')[-1]
                    print(f"EKS Cluster ARN: {self.eks_cluster_arn}")
                    print(f"EKS Cluster Name: {self.eks_cluster_name}")
                else:
                    print("Warning: Could not extract EKS cluster ARN from orchestrator config")
            elif 'Slurm' in orchestrator:
                self.cluster_type = 'slurm'
                print(f"Detected cluster type: Slurm")
            else:
                # If Orchestrator field is missing or doesn't contain Eks/Slurm, assume Slurm
                self.cluster_type = 'slurm'
                print(f"Orchestrator field not found or unrecognized, assuming cluster type: Slurm")
            
            self.cluster_arn = response.get('ClusterArn')
            self.cluster_id = self.extract_cluster_id_from_arn(self.cluster_arn)
            print(f"Cluster ID: {self.cluster_id}")
            
            if not self.cluster_id:
                print("Warning: Could not extract cluster ID from ARN")
                return []
            
            # List all nodes with pagination
            instance_ids = []
            next_token = None
            page_count = 0
            
            while True:
                page_count += 1
                print(f"Fetching nodes page {page_count}...")
                
                list_params = {'ClusterName': self.cluster_name}
                if next_token:
                    list_params['NextToken'] = next_token
                
                nodes_response = self.sagemaker_client.list_cluster_nodes(**list_params)
                
                current_page_nodes = nodes_response.get('ClusterNodeSummaries', [])
                print(f"Found {len(current_page_nodes)} nodes on page {page_count}")
                
                for node in current_page_nodes:
                    instance_id = node.get('InstanceId')
                    if instance_id:
                        instance_ids.append({
                            'InstanceId': instance_id,
                            'NodeGroup': node.get('InstanceGroupName', 'unknown'),
                            'InstanceType': node.get('InstanceType', 'unknown'),
                            'InstanceStatus': node.get('InstanceStatus', {}).get('Status', 'unknown')
                        })
                
                next_token = nodes_response.get('NextToken')
                if not next_token:
                    break
            
            print(f"Total instances found: {len(instance_ids)}")
            return instance_ids
            
        except Exception as e:
            print(f"Error getting cluster nodes: {e}")
            raise
    
    def resolve_node_identifiers(self, node_identifiers: List[str]) -> List[str]:
        """Resolve node identifiers to instance IDs.
        
        Supports multiple formats:
        - Instance IDs: i-0123456789abcdef0 (EKS and Slurm)
        - Slurm node names: ip-10-1-104-161 (Slurm only)
        - EKS node names: hyperpod-i-0123456789abcdef0 (EKS only)
        
        Returns list of instance IDs.
        """
        if not node_identifiers:
            return []
        
        # Separate different identifier types
        instance_ids = []
        slurm_node_names = []
        eks_node_names = []
        
        for identifier in node_identifiers:
            if identifier.startswith('i-'):
                # This is an instance ID
                instance_ids.append(identifier)
            elif identifier.startswith('ip-'):
                # This looks like a Slurm node name
                slurm_node_names.append(identifier)
            elif identifier.startswith('hyperpod-i-'):
                # This looks like an EKS node name (hyperpod-i-*)
                eks_node_names.append(identifier)
            else:
                # Unknown format, treat as instance ID and let validation fail later
                instance_ids.append(identifier)
        
        # Resolve EKS node names if present
        if eks_node_names:
            if self.cluster_type == 'eks':
                print(f"Resolving EKS node names to instance IDs...")
                for eks_name in eks_node_names:
                    # Extract instance ID from hyperpod-i-* format
                    # Format: hyperpod-i-0123456789abcdef0
                    if eks_name.startswith('hyperpod-'):
                        extracted_id = eks_name[9:]  # Remove 'hyperpod-' prefix
                        if extracted_id.startswith('i-'):
                            instance_ids.append(extracted_id)
                            print(f"  {eks_name} -> {extracted_id}")
                        else:
                            print(f"  Warning: Invalid EKS node name format '{eks_name}' (expected hyperpod-i-*)")
                    else:
                        print(f"  Warning: Invalid EKS node name format '{eks_name}'")
            else:
                print(f"Warning: EKS node names provided but cluster type is {self.cluster_type}")
                print(f"  EKS node names (hyperpod-i-*) are only supported for EKS clusters")
                print(f"  Ignoring: {', '.join(eks_node_names)}")
        
        # Resolve Slurm node names if present
        if slurm_node_names:
            if self.cluster_type == 'slurm':
                print(f"Resolving Slurm node names to instance IDs...")
                
                # Build a mapping of Slurm node name to instance ID
                slurm_to_instance = {}
                
                for node in self.nodes:
                    instance_id = node.get('InstanceId')
                    if instance_id:
                        slurm_name = self.get_slurm_node_name(instance_id)
                        if slurm_name:
                            slurm_to_instance[slurm_name] = instance_id
                
                # Resolve the requested Slurm node names
                for slurm_name in slurm_node_names:
                    if slurm_name in slurm_to_instance:
                        resolved_id = slurm_to_instance[slurm_name]
                        instance_ids.append(resolved_id)
                        print(f"  {slurm_name} -> {resolved_id}")
                    else:
                        print(f"  Warning: Slurm node name '{slurm_name}' not found in cluster")
            else:
                print(f"Warning: Slurm node names provided but cluster type is {self.cluster_type}")
                print(f"  Slurm node names (ip-*) are only supported for Slurm clusters")
                print(f"  Ignoring: {', '.join(slurm_node_names)}")
        
        return instance_ids
    
    def generate_collector_script(self, commands: List[str]) -> str:
        """Generate the bash script that will run on each node.
        Instance group and ID are passed as environment variables.
        Script content varies based on cluster type (EKS vs Slurm)."""
        script_lines = [
            "#!/bin/bash",
            "# HyperPod Issue Report Collector Script",
            "# Auto-generated script to collect diagnostic information",
            "# Expects INSTANCE_GROUP, INSTANCE_ID, and CLUSTER_TYPE environment variables",
            "",
            "# Note: We don't use 'set -e' because some commands (like grep) may return non-zero",
            "# exit codes even when they succeed (e.g., grep returns 1 when no matches found)",
            "",
            "# Validate required environment variables",
            "if [ -z \"${INSTANCE_GROUP}\" ] || [ -z \"${INSTANCE_ID}\" ] || [ -z \"${CLUSTER_TYPE}\" ]; then",
            "    echo \"Error: INSTANCE_GROUP, INSTANCE_ID, and CLUSTER_TYPE environment variables are required\"",
            "    exit 1",
            "fi",
            "",
            "# Instance identification",
            "TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)",
            "OUTPUT_DIR=\"/tmp/hyperpod_report_${INSTANCE_GROUP}_${INSTANCE_ID}_${TIMESTAMP}\"",
            "",
            "echo \"Creating output directory: ${OUTPUT_DIR}\"",
            "mkdir -p \"${OUTPUT_DIR}\"",
            "if [ $? -ne 0 ]; then",
            "    echo \"ERROR: Failed to create output directory\"",
            "    exit 1",
            "fi",
            "",
            "# Collect system information",
            "echo \"Collecting system information...\"",
            "echo \"${INSTANCE_GROUP}\" > \"${OUTPUT_DIR}/instance_group.txt\"",
            "echo \"${INSTANCE_ID}\" > \"${OUTPUT_DIR}/instance_id.txt\"",
            "echo \"${CLUSTER_TYPE}\" > \"${OUTPUT_DIR}/cluster_type.txt\"",
            "hostname > \"${OUTPUT_DIR}/hostname.txt\"",
            "date -u > \"${OUTPUT_DIR}/timestamp.txt\"",
            "",
            "# Collect HyperPod resource config if available",
            "if [ -f /opt/ml/config/resource_config.json ]; then",
            "    echo \"Collecting HyperPod resource config...\"",
            "    cp /opt/ml/config/resource_config.json \"${OUTPUT_DIR}/resource_config.json\" 2>/dev/null || echo \"Could not copy resource_config.json\"",
            "fi",
            "",
            "# Collect cluster logs if available",
            "if [ -d /var/log/aws/clusters ]; then",
            "    echo \"Collecting cluster logs...\"",
            "    mkdir -p \"${OUTPUT_DIR}/cluster_logs\"",
            "    cp -r /var/log/aws/clusters/* \"${OUTPUT_DIR}/cluster_logs/\" 2>/dev/null || echo \"Could not copy cluster logs\"",
            "fi",
            "",
            "# Collect systemd service status",
            "echo \"Collecting systemd service status...\"",
            "systemctl list-units --type=service --all --no-pager > \"${OUTPUT_DIR}/systemd_services.txt\" 2>&1 || echo \"Could not collect systemd services\"",
            "",
            "# Collect disk usage",
            "echo \"Collecting disk usage...\"",
            "df > \"${OUTPUT_DIR}/disk_usage.txt\" 2>&1 || echo \"Could not collect disk usage\"",
            "",
            "# Collect nvidia-smi output",
            "echo \"Collecting nvidia-smi output...\"",
            "nvidia-smi > \"${OUTPUT_DIR}/nvidia_smi.txt\" 2>&1 || echo \"nvidia-smi not available or failed\"",
            "",
        ]
        
        # Add cluster-type specific collections
        if self.cluster_type == 'eks':
            script_lines.extend([
                "# EKS-specific collections",
                "echo \"Collecting containerd service status...\"",
                "systemctl status containerd > \"${OUTPUT_DIR}/containerd_status.txt\" 2>&1 || echo \"containerd service not found or not running\"",
                "",
                "echo \"Collecting kubelet service status...\"",
                "systemctl status kubelet > \"${OUTPUT_DIR}/kubelet_status.txt\" 2>&1 || echo \"kubelet service not found or not running\"",
                "",
                "echo \"Running EKS log collector...\"",
                "# Pinned to specific commit for reproducibility; update hash when bumping",
                "EKS_LOG_COLLECTOR_URL=\"https://raw.githubusercontent.com/awslabs/amazon-eks-ami/2ac5fc03a8030bb8bc3c1fc1e810209118a10656/log-collector-script/linux/eks-log-collector.sh\"",
                "EKS_LOG_COLLECTOR_SHA256=\"61c8940e9391330a9c67d8cd6720de3de3a1a90021546835f7f54f1fed2efb3f\"",
                "curl -f -o /tmp/eks-log-collector.sh \"${EKS_LOG_COLLECTOR_URL}\"",  # nosec B108 - remote node shell script, not local Python
                "if [ $? -ne 0 ]; then",
                "    echo \"ERROR: Failed to download EKS log collector script\"",
                "    exit 1",
                "fi",
                "",
                "# Verify integrity with embedded SHA256 checksum",
                "ACTUAL_SHA=$(sha256sum /tmp/eks-log-collector.sh | awk '{print $1}')",
                "if [ \"${ACTUAL_SHA}\" != \"${EKS_LOG_COLLECTOR_SHA256}\" ]; then",
                "    echo \"ERROR: SHA256 checksum verification failed for EKS log collector\"",
                "    echo \"Expected: ${EKS_LOG_COLLECTOR_SHA256}\"",
                "    echo \"Actual:   ${ACTUAL_SHA}\"",
                "    rm -f /tmp/eks-log-collector.sh",
                "    exit 1",
                "fi",
                "echo \"SHA256 checksum verified for EKS log collector\"",
                "",
                "chmod +x /tmp/eks-log-collector.sh",
                "",
                "# Run the collector and capture its output",
                "/tmp/eks-log-collector.sh > \"${OUTPUT_DIR}/eks-log-collector-output.txt\" 2>&1 || echo \"EKS log collector completed with warnings\"",
                "",
                "# Find the generated tarball (it's created in /var/log/)",
                "EKS_TARBALL=$(ls -t /var/log/eks_*.tar.gz 2>/dev/null | head -1)",
                "if [ -n \"${EKS_TARBALL}\" ]; then",
                "    echo \"Found EKS logs at ${EKS_TARBALL}\"",
                "    echo \"Extracting EKS logs from ${EKS_TARBALL}\"",
                "    mkdir -p \"${OUTPUT_DIR}/eks-logs\"",
                "    tar -xzf \"${EKS_TARBALL}\" -C \"${OUTPUT_DIR}/eks-logs\" 2>/dev/null || echo \"Extracted EKS logs\"",
                "    rm -f \"${EKS_TARBALL}\"",
                "else",
                "    echo \"ERROR: No EKS log tarball found in /var/log/\" | tee -a \"${OUTPUT_DIR}/eks-log-collector-output.txt\"",
                "    echo \"EKS log collector may have failed. Check eks-log-collector-output.txt for details.\" | tee -a \"${OUTPUT_DIR}/eks-log-collector-output.txt\"",
                "    rm -f /tmp/eks-log-collector.sh",
                "    exit 1",
                "fi",
                "",
                "# Clean up the collector script",
                "rm -f /tmp/eks-log-collector.sh",
                "",
            ])
        elif self.cluster_type == 'slurm':
            script_lines.extend([
                "# Slurm-specific collections",
                "echo \"Collecting Slurm information...\"",
                "",
                "# Slurm info commands",
                "sinfo > \"${OUTPUT_DIR}/sinfo.txt\" 2>&1 || echo \"sinfo not available\"",
                "sinfo -R > \"${OUTPUT_DIR}/sinfo_R.txt\" 2>&1 || echo \"sinfo -R not available\"",
                "",
                "# Slurm service status",
                "systemctl status slurmctld > \"${OUTPUT_DIR}/slurmctld_status.txt\" 2>&1 || echo \"slurmctld not running on this node\"",
                "systemctl status slurmd > \"${OUTPUT_DIR}/slurmd_status.txt\" 2>&1 || echo \"slurmd not running on this node\"",
                "",
                "# Slurm configuration",
                "if [ -d /opt/slurm/etc ]; then",
                "    echo \"Collecting Slurm configuration...\"",
                "    mkdir -p \"${OUTPUT_DIR}/opt_slurm_etc\"",
                "    cp -r /opt/slurm/etc/* \"${OUTPUT_DIR}/opt_slurm_etc/\" 2>/dev/null || echo \"Could not copy Slurm config\"",
                "fi",
                "",
                "# NVIDIA bug report",
                "echo \"Running nvidia-bug-report.sh...\"",
                "nvidia-bug-report.sh --output-file \"${OUTPUT_DIR}/nvidia-bug-report.log.gz\" 2>&1 || echo \"nvidia-bug-report.sh not available or failed\"",
                "",
                "# System logs",
                "echo \"Collecting system logs...\"",
                "cp /var/log/syslog \"${OUTPUT_DIR}/syslog\" 2>/dev/null || echo \"Could not copy syslog\"",
                "cp /var/log/kern.log \"${OUTPUT_DIR}/kern.log\" 2>/dev/null || echo \"Could not copy kern.log\"",
                "dmesg -T > \"${OUTPUT_DIR}/dmesg_T.txt\" 2>&1 || echo \"Could not run dmesg -T\"",
                "",
                "# Slurm logs",
                "if [ -d /var/log/slurm ]; then",
                "    echo \"Collecting Slurm logs...\"",
                "    mkdir -p \"${OUTPUT_DIR}/var_log_slurm\"",
                "    cp -r /var/log/slurm/* \"${OUTPUT_DIR}/var_log_slurm/\" 2>/dev/null || echo \"Could not copy Slurm logs\"",
                "fi",
                "",
            ])
        
        # Add each command to the script
        for i, cmd in enumerate(commands, 1):
            # Sanitize command for filename - replace problematic characters
            safe_name = cmd.replace(' ', '_').replace('/', '_').replace('|', '_').replace('>', '_').replace('<', '_').replace('&', '_').replace(';', '_').replace('(', '_').replace(')', '_').replace('$', '_').replace('`', '_').replace('"', '_').replace("'", '_')[:50]
            output_file = f"command_{i:02d}_{safe_name}.txt"

            # Use shlex.quote() to safely escape the command for display in echo
            quoted_cmd = shlex.quote(cmd)

            cmd_line = f"{cmd} > \"${{OUTPUT_DIR}}/{output_file}\" 2>&1 || echo \"Command failed with exit code $?\" >> \"${{OUTPUT_DIR}}/{output_file}\""

            script_lines.extend([
                f"# Command {i}",
                f"echo 'Running: '{quoted_cmd}",
                cmd_line,
                "",
            ])
        
        # Add S3 upload logic with new filename format
        script_lines.extend([
            "# Upload results to S3",
            f"S3_BUCKET={shlex.quote(self.s3_bucket)}",
            f"S3_PREFIX={shlex.quote(self.report_s3_key + '/instances')}",
            "",
            "echo \"Creating tarball...\"",
            "TARBALL=\"/tmp/${INSTANCE_GROUP}_${INSTANCE_ID}.tar.gz\"",
            "tar -czf \"${TARBALL}\" -C /tmp \"$(basename ${OUTPUT_DIR})\"",
            "if [ $? -ne 0 ]; then",
            "    echo \"ERROR: Failed to create tarball\"",
            "    exit 1",
            "fi",
            "",
            "echo \"Uploading to S3...\"",
            "aws s3 cp \"${TARBALL}\" \"s3://${S3_BUCKET}/${S3_PREFIX}/$(basename ${TARBALL})\"",
            "",
            "if [ $? -eq 0 ]; then",
            "    echo \"Successfully uploaded report to s3://${S3_BUCKET}/${S3_PREFIX}/$(basename ${TARBALL})\"",
            "    rm -rf \"${OUTPUT_DIR}\" \"${TARBALL}\"",
            "    echo \"Report collection completed for ${INSTANCE_GROUP}/${INSTANCE_ID}\"",
            "    exit 0",
            "else",
            "    echo \"ERROR: Failed to upload to S3\"",
            "    exit 1",
            "fi",
        ])
        
        return '\n'.join(script_lines)
    
    def get_hyperpod_ssm_target(self, instance_id: str, instance_group_name: str) -> str:
        """Construct the HyperPod SSM target format."""
        if not self.cluster_id:
            raise ValueError("Cluster ID is required for HyperPod SSM targets")
        return f"sagemaker-cluster:{self.cluster_id}_{instance_group_name}-{instance_id}"
    
    def execute_collection_on_node(self, node: Dict, commands: List[str], script_s3_uri: str) -> Dict:
        """Execute the collection script on a single node via SSM using pexpect."""
        instance_id = node['InstanceId']
        instance_group = node.get('NodeGroup', 'unknown')
        
        # Start timing
        start_time = time.time()
        
        try:
            ssm_target = self.get_hyperpod_ssm_target(instance_id, instance_group)
        except ValueError as e:
            return {
                'InstanceId': instance_id,
                'NodeGroup': instance_group,
                'Success': False,
                'Error': str(e),
                'ElapsedTime': time.time() - start_time
            }
        
        # Build the command to download and execute the script with environment variables
        commands_to_run = [
            f"aws s3 cp {shlex.quote(script_s3_uri)} /tmp/collector_script.sh",
            "chmod +x /tmp/collector_script.sh",
            f"INSTANCE_GROUP={shlex.quote(instance_group)} INSTANCE_ID={shlex.quote(instance_id)} CLUSTER_TYPE={shlex.quote(self.cluster_type)} /tmp/collector_script.sh"
        ]
        
        full_command = " && ".join(commands_to_run)
        
        print(f"Executing collection on {instance_id} ({instance_group})...")
        
        child = None
        custom_prompt = "PEXPECT_READY# "
        
        try:
            ssm_command = ['aws', 'ssm', 'start-session', '--target', ssm_target]
            if self.region:
                ssm_command.extend(['--region', self.region])

            if self.debug:
                print(f"[DEBUG] {instance_id}: SSM command: {ssm_command}")
                print(f"[DEBUG] {instance_id}: Full command: {full_command}")

            # Use pexpect to handle the interactive session
            # Note: No default timeout set - each expect() call has explicit timeout
            child = pexpect.spawn(ssm_command[0], ssm_command[1:], encoding='utf-8')
            child.logfile_read = None
            
            # Wait for initial prompt (60 seconds to handle slow SSM session initialization)
            initial_prompt_patterns = [
                r'[\$#]\s+',            # Standard shell prompt
                r'sh-\d+\.\d+[\$#]\s*', # sh prompt
                pexpect.TIMEOUT
            ]
            
            prompt_index = child.expect(initial_prompt_patterns, timeout=SSM_PROMPT_TIMEOUT)
            
            if prompt_index == len(initial_prompt_patterns) - 1:  # TIMEOUT
                # Get output for debugging
                output_sample = ""
                if child and hasattr(child, 'before') and child.before:
                    # Show more output to help diagnose the issue
                    output_sample = child.before.strip()
                    if len(output_sample) > 1000:
                        output_sample = output_sample[-1000:]  # Last 1000 chars
                
                error_msg = (
                    f"Failed to detect shell prompt after 60 seconds.\n"
                    f"This may indicate:\n"
                    f"  - Custom SSM session configuration interfering with prompt detection\n"
                    f"  - Non-standard shell prompt format\n"
                    f"  - SSM session initialization issues\n"
                )
                
                if output_sample:
                    error_msg += f"\nSession output received:\n{output_sample}\n"
                    error_msg += (
                        f"\nExpected prompt patterns: $ or # followed by space\n"
                        f"If your cluster uses custom SSM session commands or non-standard prompts,\n"
                        f"this tool may not be compatible."
                    )
                else:
                    error_msg += "\nNo output received from SSM session."
                
                return {
                    'InstanceId': instance_id,
                    'NodeGroup': instance_group,
                    'Success': False,
                    'Error': error_msg
                }
            
            # Set custom prompt
            child.sendline(f'export PS1="{custom_prompt}"')
            child.sendline('echo "PROMPT_SET_MARKER"')
            child.expect('PROMPT_SET_MARKER', timeout=SSM_PROMPT_TIMEOUT)
            child.expect(custom_prompt, timeout=SSM_PROMPT_TIMEOUT)
            
            if self.debug:
                print(f"[DEBUG] {instance_id}: Custom prompt set")
            
            # Execute the command and capture exit code immediately
            child.sendline(f'{full_command}; EXIT_CODE=$?; echo "EXIT_CODE:$EXIT_CODE"')
            
            # Wait for command completion (15 minutes for script execution)
            child.expect(custom_prompt, timeout=SSM_SCRIPT_EXECUTION_TIMEOUT)
            
            # Extract output
            output = child.before
            exit_code = 1  # Default to failure
            
            if output:
                lines = output.split('\n')
                cleaned_lines = []
                command_echo_removed = False
                
                for line in lines:
                    line_stripped = line.strip()
                    
                    # Remove command echo
                    if not command_echo_removed and full_command in line:
                        command_echo_removed = True
                        continue
                    
                    # Extract exit code
                    if line_stripped.startswith('EXIT_CODE:'):
                        try:
                            exit_code = int(line_stripped.split(':')[1].strip())
                        except (ValueError, IndexError):
                            pass
                        continue
                    
                    if line_stripped:
                        cleaned_lines.append(line_stripped)
                
                output = '\n'.join(cleaned_lines)
            else:
                output = ""
            
            # Close session
            try:
                child.sendline('exit')
                child.expect(pexpect.EOF, timeout=5)
            except Exception:
                try:
                    child.kill(signal.SIGINT)
                except Exception:  # nosec B110 - best-effort cleanup
                    pass
            
            # Determine success based on exit code OR successful S3 upload message
            # Some nodes may not properly echo the EXIT_CODE line due to terminal issues
            success_indicators = [
                exit_code == 0,
                'Successfully uploaded report to s3://' in output,
                'upload: ../../tmp/' in output and '.tar.gz to s3://' in output
            ]
            
            if any(success_indicators):
                return {
                    'InstanceId': instance_id,
                    'NodeGroup': instance_group,
                    'Success': True,
                    'Output': output,
                    'ElapsedTime': time.time() - start_time
                }
            else:
                # Show last 15 lines of output which usually contain the error
                output_lines = output.split('\n')
                error_context = '\n'.join(output_lines[-15:]) if len(output_lines) > 15 else output
                
                return {
                    'InstanceId': instance_id,
                    'NodeGroup': instance_group,
                    'Success': False,
                    'Error': f"Script execution failed (exit code: {exit_code})\n{error_context}",
                    'Output': output,
                    'ElapsedTime': time.time() - start_time
                }
            
        except pexpect.TIMEOUT:
            # Show more context about where the timeout occurred
            output_sample = ""
            if child and hasattr(child, 'before') and child.before:
                output_sample = child.before.strip()
                if len(output_sample) > 1000:
                    output_sample = output_sample[-1000:]  # Last 1000 chars
            
            error_msg = (
                f"Operation timed out during command execution.\n"
                f"This may indicate:\n"
                f"  - Command taking longer than expected to complete\n"
                f"  - Custom shell configuration interfering with output detection\n"
                f"  - Network or SSM session issues\n"
            )
            
            if output_sample:
                error_msg += f"\nLast output received:\n{output_sample}"
            else:
                error_msg += "\nNo output received."
            
            return {
                'InstanceId': instance_id,
                'NodeGroup': instance_group,
                'Success': False,
                'Error': error_msg,
                'ElapsedTime': time.time() - start_time
            }
            
        except pexpect.EOF:
            output_sample = ""
            if child and hasattr(child, 'before') and child.before:
                output_sample = child.before.strip()
                if len(output_sample) > 500:
                    output_sample = output_sample[-500:]  # Last 500 chars
            
            error_msg = "SSM session ended unexpectedly"
            if output_sample:
                error_msg += f"\nLast output:\n{output_sample}"
            
            return {
                'InstanceId': instance_id,
                'NodeGroup': instance_group,
                'Success': False,
                'Error': error_msg,
                'ElapsedTime': time.time() - start_time
            }
            
        except Exception as e:
            error_msg = f"Error executing command: {str(e)}"
            if self.debug:
                error_msg += f"\nTraceback: {traceback.format_exc()}"
            return {
                'InstanceId': instance_id,
                'NodeGroup': instance_group,
                'Success': False,
                'Error': error_msg,
                'ElapsedTime': time.time() - start_time
            }
            
        finally:
            if child and child.isalive():
                try:
                    child.terminate(force=True)
                except Exception:  # nosec B110 - best-effort cleanup
                    pass
    
    def execute_with_retry(self, node: Dict, commands: List[str], script_s3_uri: str, max_retries: int = 3) -> Dict:
        """Execute collection on a node with exponential backoff on throttling errors."""
        for attempt in range(max_retries):
            result = self.execute_collection_on_node(node, commands, script_s3_uri)
            
            error_msg = result.get('Error', '')
            if 'ThrottlingException' in error_msg or 'Rate exceeded' in error_msg:
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt
                    if self.debug:
                        print(f"[DEBUG] {node['InstanceId']}: Throttled, retrying in {wait_time}s (attempt {attempt + 1}/{max_retries})")
                    time.sleep(wait_time)
                    continue
            
            return result
        
        return result

    def collect_reports(self, commands: List[str], instance_groups: Optional[List[str]] = None, instance_ids: Optional[List[str]] = None, max_workers: int = 16):
        """Collect reports from all nodes, specific instance groups, or specific instance IDs.
        
        For Slurm clusters, instance_ids can be either:
        - Instance IDs: i-0123456789abcdef0
        - Slurm node names: ip-10-1-104-161
        
        Note: max_workers defaults to 16 to balance speed and avoid SSM throttling on large clusters.
        """
        # Get cluster nodes
        self.nodes = self.get_cluster_nodes()
        
        if not self.nodes:
            print("No nodes found in cluster")
            return
        
        # Collect kubectl information first (for EKS clusters)
        if self.cluster_type == 'eks':
            self.collect_kubectl_node_info()
        
        # Filter by specific instance IDs or Slurm node names if specified
        if instance_ids:
            # Resolve node identifiers (handles both instance IDs and Slurm node names)
            resolved_instance_ids = self.resolve_node_identifiers(instance_ids)
            
            if not resolved_instance_ids:
                print(f"No valid nodes found from specified identifiers: {', '.join(instance_ids)}")
                return
            
            self.nodes = [n for n in self.nodes if n.get('InstanceId') in resolved_instance_ids]
            if not self.nodes:
                print(f"No nodes found with specified identifiers: {', '.join(instance_ids)}")
                return
            
            # Show which requested identifiers were not found
            found_ids = {n.get('InstanceId') for n in self.nodes}
            missing_ids = set(resolved_instance_ids) - found_ids
            if missing_ids:
                print(f"Warning: Instance IDs not found in cluster: {', '.join(missing_ids)}")
        # Filter by instance groups if specified (only if instance_ids not specified)
        elif instance_groups:
            # Convert instance groups to lowercase for case-insensitive matching
            instance_groups_lower = [ig.lower() for ig in instance_groups]
            self.nodes = [n for n in self.nodes if n.get('NodeGroup', '').lower() in instance_groups_lower]
            if not self.nodes:
                print(f"No nodes found in instance groups: {', '.join(instance_groups)}")
                return
            print(f"Filtering to instance groups: {', '.join(instance_groups)}")
        
        print(f"\nCollecting reports from {len(self.nodes)} nodes")
        print(f"Cluster type: {self.cluster_type.upper()}")
        print(f"Report ID: {self.report_id}")
        print(f"S3 Location: s3://{self.s3_bucket}/{self.report_s3_key}/")
        
        # Show what will be collected based on cluster type
        if self.cluster_type == 'eks':
            print(f"Default collections: nvidia-smi, containerd status, kubelet status, EKS log collector, resource config, cluster logs, systemd services, disk usage")
        elif self.cluster_type == 'slurm':
            print(f"Default collections: nvidia-smi, nvidia-bug-report, sinfo, Slurm services, Slurm config, Slurm logs, system logs")
        
        if commands:
            print(f"Additional commands: {', '.join(commands)}")
        print("-" * 60)
        
        # Generate and upload the collector script once
        script_content = self.generate_collector_script(commands)
        script_key = f"{self.report_s3_key}/collector_script.sh"
        
        try:
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=script_key,
                Body=script_content.encode('utf-8'),
                ContentType='text/x-shellscript'
            )
            script_s3_uri = f"s3://{self.s3_bucket}/{script_key}"
            print(f"Uploaded collector script to: {script_s3_uri}")
        except Exception as e:
            print(f"Error uploading collector script: {e}")
            return
        
        # Execute collection on all nodes using ThreadPoolExecutor
        results = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_node = {
                executor.submit(self.execute_with_retry, node, commands, script_s3_uri): node
                for node in self.nodes
            }
            
            for future in as_completed(future_to_node):
                node = future_to_node[future]
                try:
                    result = future.result()
                    results.append(result)
                    
                    status = "✓" if result['Success'] else "✗"
                    elapsed = result.get('ElapsedTime', 0)
                    print(f"[{status}] {result['InstanceId']} ({result['NodeGroup']}) - {elapsed:.1f}s")
                    
                    if not result['Success']:
                        error_msg = result.get('Error', 'Unknown error')
                        # Print error details with indentation for readability
                        for line in error_msg.split('\n'):
                            if line.strip():
                                print(f"    {line}")
                    
                except Exception as e:
                    print(f"[✗] {node['InstanceId']}: Exception: {e}")
                    results.append({
                        'InstanceId': node['InstanceId'],
                        'NodeGroup': node.get('NodeGroup', 'unknown'),
                        'Success': False,
                        'Error': str(e),
                        'ElapsedTime': 0
                    })
        
        # Save summary
        summary_saved = self.save_summary(results)

        print("-" * 60)
        print(f"\nReport collection completed!")
        print(f"Instance reports uploaded to: s3://{self.s3_bucket}/{self.report_s3_key}/instances/")
        if summary_saved:
            print(f"Summary: s3://{self.s3_bucket}/{self.report_s3_key}/summary.json")
        else:
            print("Warning: Summary upload failed — see error above")
        
        # Print statistics
        successful = sum(1 for r in results if r['Success'])
        failed = len(results) - successful
        print(f"\nStatistics:")
        print(f"  Total nodes: {len(results)}")
        print(f"  Successful: {successful}")
        print(f"  Failed: {failed}")
        
        # Offer to download results
        self.offer_download_results()
    
    def offer_download_results(self):
        """Ask user if they want to download results from S3."""
        print("\n" + "=" * 60)
        print("Download Results")
        print("=" * 60)
        
        try:
            response = input("\nWould you like to download all results from S3 to the current directory? (y/n): ").strip().lower()
            
            if response in ['y', 'yes']:
                download_dir = self.download_results_from_s3()
                
                if download_dir:
                    # Ask about creating zip archive
                    response = input("\nWould you like to create a zip archive of the downloaded results? (y/n): ").strip().lower()
                    
                    if response in ['y', 'yes']:
                        self.create_zip_archive(download_dir)
            else:
                print("\nSkipping download. You can download manually using:")
                print(f"  aws s3 sync s3://{self.s3_bucket}/{self.report_s3_key}/ ./{self.cluster_name}_{self.report_id}/")
                
        except KeyboardInterrupt:
            print("\n\nDownload cancelled by user.")
        except Exception as e:
            print(f"\nError during download prompt: {e}")
    
    def download_results_from_s3(self) -> Optional[str]:
        """Download all results from S3 to local directory.
        
        Returns:
            str: Path to download directory if successful, None otherwise
        """
        # Create download directory
        download_dir = f"{self.cluster_name}_{self.report_id}"
        
        print(f"\nDownloading results to: ./{download_dir}/")
        print(f"Source: s3://{self.s3_bucket}/{self.report_s3_key}/")
        
        try:
            # List all objects in the S3 prefix
            paginator = self.s3_client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=self.s3_bucket, Prefix=self.report_s3_key)
            
            files_to_download = []
            for page in pages:
                if 'Contents' in page:
                    for obj in page['Contents']:
                        key = obj['Key']
                        # Skip the prefix itself (directory marker)
                        if key != self.report_s3_key and key != f"{self.report_s3_key}/":
                            files_to_download.append(key)
            
            if not files_to_download:
                print("No files found to download.")
                return None
            
            print(f"Found {len(files_to_download)} files to download...")
            
            # Download each file
            downloaded = 0
            failed = 0
            
            for key in files_to_download:
                # Calculate relative path (remove the report_s3_key prefix)
                relative_path = key[len(self.report_s3_key):].lstrip('/')
                local_path = os.path.join(download_dir, relative_path)
                
                # Create parent directory if needed
                local_dir = os.path.dirname(local_path)
                if local_dir:
                    os.makedirs(local_dir, exist_ok=True)
                
                try:
                    # Download file
                    self.s3_client.download_file(self.s3_bucket, key, local_path)
                    downloaded += 1
                    
                    # Show progress for every 5 files or last file
                    if downloaded % 5 == 0 or downloaded == len(files_to_download):
                        print(f"  Downloaded {downloaded}/{len(files_to_download)} files...")
                        
                except Exception as e:
                    print(f"  Failed to download {relative_path}: {e}")
                    failed += 1
            
            print(f"\n✓ Download completed!")
            print(f"  Downloaded: {downloaded} files")
            if failed > 0:
                print(f"  Failed: {failed} files")
            print(f"  Location: ./{download_dir}/")
            
            return download_dir
            
        except Exception as e:
            print(f"\nError downloading results: {e}")
            if self.debug:
                traceback.print_exc()
            return None
    
    def create_zip_archive(self, directory: str):
        """Create a zip archive of the downloaded results.
        
        Args:
            directory: Path to directory to archive
        """
        zip_filename = f"{directory}.zip"
        
        print(f"\nCreating zip archive: {zip_filename}")
        
        try:
            with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
                # Walk through directory
                file_count = 0
                for root, dirs, files in os.walk(directory):
                    for file in files:
                        file_path = os.path.join(root, file)
                        # Calculate archive name (relative to directory)
                        arcname = os.path.relpath(file_path, os.path.dirname(directory))
                        zipf.write(file_path, arcname)
                        file_count += 1
                        
                        # Show progress
                        if file_count % 5 == 0:
                            print(f"  Archived {file_count} files...")
            
            # Get zip file size
            zip_size = os.path.getsize(zip_filename)
            zip_size_mb = zip_size / (1024 * 1024)
            
            print(f"\n✓ Zip archive created!")
            print(f"  File: {zip_filename}")
            print(f"  Size: {zip_size_mb:.2f} MB")
            print(f"  Files: {file_count}")
            
            # Ask if user wants to delete the uncompressed directory
            response = input(f"\nWould you like to delete the uncompressed directory '{directory}'? (y/n): ").strip().lower()
            
            if response in ['y', 'yes']:
                shutil.rmtree(directory)
                print(f"✓ Deleted directory: {directory}")
            else:
                print(f"Keeping directory: {directory}")
                
        except Exception as e:
            print(f"\nError creating zip archive: {e}")
            if self.debug:
                traceback.print_exc()
    
    def save_summary(self, results: List[Dict]) -> bool:
        """Save collection summary to S3. Returns True on success."""
        summary = {
            'cluster_name': self.cluster_name,
            'cluster_id': self.cluster_id,
            'report_id': self.report_id,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'total_nodes': len(results),
            'successful': sum(1 for r in results if r['Success']),
            'failed': sum(1 for r in results if not r['Success']),
            'results': results
        }

        summary_key = f"{self.report_s3_key}/summary.json"

        try:
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=summary_key,
                Body=json.dumps(summary, indent=2).encode('utf-8'),
                ContentType='application/json'
            )
            print(f"Summary saved to: s3://{self.s3_bucket}/{summary_key}")
            return True
        except Exception as e:
            print(f"Error saving summary: {e}")
            return False
    
    def verify_kubectl_config(self) -> bool:
        """Verify kubectl is configured for the EKS cluster."""
        if not self.eks_cluster_name:
            print("Warning: EKS cluster name not available, skipping kubectl verification")
            return False
        
        try:
            # Check if kubectl is installed
            result = subprocess.run(['kubectl', 'version', '--client'],  # nosec B603 B607
                                  capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                print("\n" + "!" * 60)
                print("ERROR: kubectl is not installed or not in PATH")
                print("!" * 60)
                return False
            
            # Extract just the version line
            version_line = result.stdout.strip().split('\n')[0] if result.stdout else "kubectl installed"
            print(f"kubectl version: {version_line}")
            
            # Check current context
            result = subprocess.run(['kubectl', 'config', 'current-context'],  # nosec B603 B607
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                current_context = result.stdout.strip()
                print(f"Current kubectl context: {current_context}")
                
                # Check if context matches EKS cluster
                if self.eks_cluster_name in current_context:
                    print(f"✓ kubectl is configured for EKS cluster: {self.eks_cluster_name}")
                    return True
                else:
                    # Extract region from EKS cluster ARN
                    arn_parts = self.eks_cluster_arn.split(':') if self.eks_cluster_arn else []
                    if len(arn_parts) <= 3:
                        print(f"Error: Malformed EKS cluster ARN: {self.eks_cluster_arn}")
                        return False
                    region = arn_parts[3]
                    
                    print("\n" + "!" * 60)
                    print(f"ERROR: kubectl context does not match EKS cluster")
                    print(f"Current context: {current_context}")
                    print(f"Expected cluster: {self.eks_cluster_name}")
                    print("!" * 60)
                    print("\nTo configure kubectl for this EKS cluster, run:")
                    print(f"  aws eks update-kubeconfig --name {self.eks_cluster_name} --region {region}")
                    return False
            else:
                # Extract region from EKS cluster ARN
                region = self.eks_cluster_arn.split(':')[3] if self.eks_cluster_arn else 'REGION'
                
                print("\n" + "!" * 60)
                print("ERROR: No kubectl context configured")
                print("!" * 60)
                print("\nTo configure kubectl for this EKS cluster, run:")
                print(f"  aws eks update-kubeconfig --name {self.eks_cluster_name} --region {region}")
                return False
                
        except subprocess.TimeoutExpired:
            print("Warning: kubectl command timed out")
            return False
        except FileNotFoundError:
            print("\n" + "!" * 60)
            print("ERROR: kubectl not found in PATH")
            print("!" * 60)
            return False
        except Exception as e:
            print(f"Warning: Error verifying kubectl config: {e}")
            return False

    @staticmethod
    def _save_kubectl_result(result: subprocess.CompletedProcess,
                             name: str, description: str,
                             kubectl_output_dir: str, elapsed: float,
                             successful: int, failed: int) -> tuple:
        """Save kubectl output and update counters. Returns (successful, failed)."""
        output_file = os.path.join(kubectl_output_dir, f'{name}.txt')
        if result.returncode == 0:
            if result.stdout.strip():
                with open(output_file, 'w', encoding='utf-8') as f:
                    f.write(result.stdout)
                print(f"  Collecting: {description}... ✓ ({elapsed:.1f}s)")
                successful += 1
            else:
                with open(output_file, 'w', encoding='utf-8') as f:
                    f.write("No resources found\n")
                print(f"  Collecting: {description}... ✓ (empty, {elapsed:.1f}s)")
                successful += 1
        else:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(f"Error: {result.stderr}\n")
            print(f"  Collecting: {description}... ✗ ({result.stderr.strip()[:50]}, {elapsed:.1f}s)")
            failed += 1
        return successful, failed

    def collect_kubectl_node_info(self):
        """Collect kubectl describe node information for all nodes."""
        if self.cluster_type != 'eks':
            print("Skipping kubectl collection - not an EKS cluster")
            return

        if not self.eks_cluster_name:
            print("Skipping kubectl collection - EKS cluster name not available")
            return

        print("\n" + "=" * 60)
        print("Collecting kubectl node information...")
        print("=" * 60)

        # Verify kubectl configuration - exit if not configured
        if not self.verify_kubectl_config():
            print("\n" + "!" * 60)
            print("ERROR: kubectl must be configured for EKS clusters")
            print("!" * 60)
            print("\nPlease configure kubectl and re-run the tool.\n")
            sys.exit(1)

        kubectl_output_dir = None
        tarball_path = None
        try:
            # Create output directory
            kubectl_output_dir = tempfile.mkdtemp(prefix='kubectl_output_')
            
            # Each subprocess.run uses static string arguments so security
            # linters can verify no dynamic command injection is possible.
            print("Collecting 15 Kubernetes resource types...")
            successful = 0
            failed = 0
            timeout = KUBECTL_TIMEOUT

            # High Priority - Essential for troubleshooting
            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'describe', 'nodes'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'nodes_describe', 'Node descriptions (capacity, conditions, pods)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'pods', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'pods_all_namespaces', 'All pods across namespaces (wide output)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'describe', 'pods', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'pods_describe_all_namespaces', 'Detailed pod descriptions (all namespaces)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'events', '-A', '--sort-by=.lastTimestamp'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'events_all_namespaces', 'Cluster events sorted by timestamp',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'pvc', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'pvcs_all_namespaces', 'PersistentVolumeClaims (storage)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'describe', 'pvc', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'pvcs_describe_all_namespaces', 'Detailed PVC descriptions',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'svc', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'services_all_namespaces', 'Services (network endpoints)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'describe', 'svc', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'services_describe_all_namespaces', 'Detailed service descriptions',
                kubectl_output_dir, time.time() - t, successful, failed)

            # Medium Priority - Very useful
            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'deployments', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'deployments_all_namespaces', 'Deployments',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'statefulsets', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'statefulsets_all_namespaces', 'StatefulSets',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'daemonsets', '-A', '-o', 'wide'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'daemonsets_all_namespaces', 'DaemonSets',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'configmaps', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'configmaps_all_namespaces', 'ConfigMaps (metadata only)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'secrets', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'secrets_all_namespaces', 'Secrets (metadata only, no content)',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'resourcequota', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'resourcequotas_all_namespaces', 'Resource quotas',
                kubectl_output_dir, time.time() - t, successful, failed)

            t = time.time()
            successful, failed = self._save_kubectl_result(
                subprocess.run(['kubectl', 'get', 'networkpolicies', '-A'],  # nosec B603 B607
                               capture_output=True, text=True, timeout=timeout),
                'networkpolicies_all_namespaces', 'Network policies',
                kubectl_output_dir, time.time() - t, successful, failed)
            
            print(f"\nCollection summary: {successful} successful, {failed} failed")
            
            # Create tarball with files at root level (no wrapper directory)
            print("\nCreating kubectl output tarball...")
            tarball_fd, tarball_path = tempfile.mkstemp(suffix='_kubectl_resources.tar.gz')
            os.close(tarball_fd)
            
            with tarfile.open(tarball_path, 'w:gz') as tar:
                # Add each file directly to the tarball root (no parent directory)
                for filename in os.listdir(kubectl_output_dir):
                    file_path = os.path.join(kubectl_output_dir, filename)
                    tar.add(file_path, arcname=filename)
            
            print(f"Created tarball: {tarball_path}")
            
            # Upload to S3
            s3_key = f"{self.report_s3_key}/kubectl_resources.tar.gz"
            print(f"Uploading to S3: s3://{self.s3_bucket}/{s3_key}")
            
            self.s3_client.upload_file(tarball_path, self.s3_bucket, s3_key)
            
            print(f"✓ Successfully uploaded kubectl resource information to S3")
            print(f"  Location: s3://{self.s3_bucket}/{s3_key}")

        except Exception as e:
            print(f"Error collecting kubectl information: {e}")
            if self.debug:
                traceback.print_exc()
            raise
        finally:
            # Cleanup temp files regardless of success or failure
            if kubectl_output_dir and os.path.isdir(kubectl_output_dir):
                shutil.rmtree(kubectl_output_dir, ignore_errors=True)
            if tarball_path and os.path.exists(tarball_path):
                os.remove(tarball_path)


def main():
    # Check platform compatibility
    if platform.system() == 'Windows':
        print("=" * 70)
        print("ERROR: Windows is not supported")
        print("=" * 70)
        print()
        print("This tool uses pexpect for interactive SSM sessions, which has")
        print("different behavior on Windows compared to macOS and Linux.")
        print()
        print("Supported platforms:")
        print("  - macOS")
        print("  - Linux")
        print()
        print("Please run this tool from a macOS or Linux machine, or use WSL")
        print("(Windows Subsystem for Linux) if you're on Windows.")
        print()
        sys.exit(1)
    
    parser = argparse.ArgumentParser(
        description='HyperPod Issue Report Collector - Supports both EKS and Slurm clusters',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage - auto-detects cluster type
  python hyperpod_issue_report.py --cluster my-cluster --region us-west-2 --s3-path s3://my-bucket

  # With custom prefix and additional commands
  python hyperpod_issue_report.py --cluster my-cluster --region us-west-2 --s3-path s3://my-bucket/diagnostics \\
    --command "df -h" --command "free -h"

  # Target specific instance groups
  python hyperpod_issue_report.py --cluster my-cluster --region us-west-2 --s3-path s3://my-bucket \\
    --instance-groups worker-group-1 worker-group-2

  # Target specific nodes (instance IDs, EKS names, or Slurm names)
  python hyperpod_issue_report.py --cluster my-cluster --region us-west-2 --s3-path s3://my-bucket \\
    --nodes i-abc123 hyperpod-i-044bbf66a68558e87 ip-10-1-104-161
        """
    )
    
    parser.add_argument('--cluster', '-c', required=True, help='HyperPod cluster name (EKS or Slurm)')
    parser.add_argument('--region', '-r', help='AWS region (uses default boto3 region if not specified)')
    parser.add_argument('--s3-path', '-s', required=True, help='S3 path for storing reports (e.g., s3://bucket-name/prefix or s3://bucket-name)')
    parser.add_argument('--command', '-cmd', action='append', help='Additional command to execute on nodes (can be specified multiple times)')
    parser.add_argument('--instance-groups', '-g', nargs='+', help='Target specific instance groups (e.g., --instance-groups worker1 worker2)')
    parser.add_argument('--max-workers', '-w', type=int, default=16, help='Maximum concurrent SSM sessions (default: 16, reduce if hitting throttling)')
    parser.add_argument('--nodes', '-n', nargs='+', help='Target specific nodes: instance IDs (i-*), EKS node names (hyperpod-i-*), or Slurm node names (ip-*)')
    parser.add_argument('--debug', '-d', action='store_true', help='Enable debug mode')
    
    args = parser.parse_args()
    
    # Validate mutually exclusive options
    if args.instance_groups and args.nodes:
        print("Error: --instance-groups and --nodes cannot be used together")
        sys.exit(1)
    
    try:
        collector = HyperPodIssueReportCollector(
            cluster_name=args.cluster,
            s3_path=args.s3_path,
            region=args.region,
            debug=args.debug
        )
        
        # User-specified commands
        commands = []
        
        # Add any user-specified commands
        if args.command:
            commands.extend(args.command)
        
        collector.collect_reports(
            commands=commands,
            instance_groups=args.instance_groups,
            instance_ids=args.nodes,
            max_workers=args.max_workers
        )
        
    except KeyboardInterrupt:
        print("\n\nInterrupted by user. Exiting...")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        if args.debug:
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
