# RDS/Aurora Instance Sizing Guide

## Instance Family Selection

### Graviton (ARM) — Default Recommendation

Graviton-based instances (r7g, r6g, m7g, t4g) offer ~20% better price-performance than Intel equivalents. Default to Graviton unless the workload requires x86-specific extensions.

| Family | Use Case | vCPU Range | Memory Range |
|---|---|---|---|
| **db.r7g** | Memory-optimized production (default choice) | 2-64 | 16-512 GiB |
| **db.r6g** | Previous-gen memory-optimized (still cost-effective) | 2-64 | 16-512 GiB |
| **db.r7i** | x86 memory-optimized (when Graviton incompatible) | 2-64 | 16-512 GiB |
| **db.m7g** | General purpose (balanced CPU/memory) | 2-64 | 8-256 GiB |
| **db.t4g** | Burstable, dev/test, small production | 2-8 | 4-32 GiB |
| **db.x2g** | Memory-intensive (large in-memory datasets) | 4-64 | 64-1024 GiB |

### When to Use Each Family

- **r7g (default)**: Most production OLTP workloads. Memory-heavy databases benefit from the 8:1 memory-to-vCPU ratio.
- **m7g**: Workloads that are CPU-bound rather than memory-bound. Lower memory-to-vCPU ratio (4:1) at lower cost.
- **t4g**: Development, staging, low-traffic production. Burstable CPU is fine when utilization is <40% average. Enable unlimited mode for production to avoid CPU throttling.
- **x2g**: Data warehousing workloads, very large working sets that must fit in buffer pool to avoid disk I/O.

## Memory-to-Connections Ratios

### PostgreSQL

Each PostgreSQL connection consumes approximately 5-10 MB of memory at baseline. Under heavy query load, connections can consume 50-200 MB each (work_mem allocations).

| Instance Size | Memory | Recommended max_connections | Notes |
|---|---|---|---|
| db.t4g.micro | 1 GiB | 25 | Dev/test only |
| db.t4g.medium | 4 GiB | 100 | Small production |
| db.r7g.large | 16 GiB | 200-400 | Standard production |
| db.r7g.xlarge | 32 GiB | 400-800 | Medium production |
| db.r7g.2xlarge | 64 GiB | 800-1500 | Large production |
| db.r7g.4xlarge | 128 GiB | 1500-3000 | Heavy production |

**Rule of thumb**: Reserve 25% of memory for shared_buffers, 10% for OS/overhead, and allocate remaining memory across max_connections assuming 10-20 MB per connection under load.

### MySQL

MySQL connections are lighter (~1-5 MB each at baseline) but InnoDB buffer pool should claim 75% of memory.

| Instance Size | Memory | Recommended max_connections | Notes |
|---|---|---|---|
| db.t4g.micro | 1 GiB | 50 | Dev/test only |
| db.t4g.medium | 4 GiB | 150 | Small production |
| db.r7g.large | 16 GiB | 500-1000 | Standard production |
| db.r7g.xlarge | 32 GiB | 1000-2000 | Medium production |
| db.r7g.2xlarge | 64 GiB | 2000-4000 | Large production |

**Rule of thumb**: `innodb_buffer_pool_size` = 75% of memory. Remaining 25% for connections, temp tables, sort buffers, and OS.

## Aurora Serverless v2 ACU Sizing

1 ACU = approximately 2 GiB RAM + proportional CPU + networking.

| Workload | Min ACU | Max ACU | Notes |
|---|---|---|---|
| Dev/test | 0.5 | 2 | Minimal cost, slow at minimum |
| Small production | 1 | 8 | Handles moderate traffic spikes |
| Medium production | 2 | 32 | Good for typical web apps |
| Large production (reader) | 4 | 64 | Heavy read workloads |
| Large production (writer) | 8 | 128 | Consider provisioned if sustained |

**Sizing approach**: Start with min=0.5, max=16 for new workloads. Monitor `ServerlessDatabaseCapacity` and `ACUUtilization` metrics for 2 weeks, then tighten the range. Set max ACU high enough that the database never throttles — it only costs more when it scales up.

## Right-Sizing Process

1. Enable Performance Insights (free tier: 7-day retention)
2. Run production workload for at least 1 week
3. Check `db.load` — if average load < 1.0 and max load < vCPU count, the instance is oversized
4. Check `FreeableMemory` — if consistently >50% of total memory, consider downsizing
5. Check `CPUUtilization` — if average <30%, consider smaller instance or Graviton migration
6. For Aurora Serverless v2: check `ServerlessDatabaseCapacity` — if min ACU is never reached, lower it

## Storage Sizing

### RDS (EBS-Backed)

| Storage Type | IOPS | Throughput | Use Case |
|---|---|---|---|
| **gp3** (default) | 3,000 baseline, up to 16,000 | 125 MiB/s baseline, up to 1,000 MiB/s | Most workloads |
| **io2 Block Express** | Up to 256,000 | Up to 4,000 MiB/s | I/O intensive, latency sensitive |

**gp3 tips**:
- Free IOPS/throughput increase: gp3 baseline is 3,000 IOPS / 125 MiB/s regardless of volume size
- Provision additional IOPS only when CloudWatch shows `VolumeReadOps` + `VolumeWriteOps` consistently approaching 3,000/sec
- Storage auto-scaling: enable and set max threshold to avoid running out of space

### Aurora (Managed Storage)

- Storage auto-grows in 10 GiB increments up to 128 TiB
- No IOPS provisioning needed — Aurora handles I/O distribution
- I/O-Optimized cluster option: eliminates per-I/O charges for I/O-heavy workloads (>25% of database cost is I/O)
- Standard pricing includes I/O charges per million requests — suitable for most workloads

## Cost Optimization Patterns

### Reserved Instances
- 1-year all-upfront: ~30-40% savings over on-demand
- 3-year all-upfront: ~50-60% savings over on-demand
- Apply to the writer instance (always running); use Serverless v2 for variable readers

### Graviton Migration
- Direct ~20% cost reduction with no application changes for most workloads
- MySQL and PostgreSQL are fully compatible
- Use blue/green deployment for zero-downtime migration from Intel to Graviton

### Aurora I/O-Optimized vs Standard
- Calculate: if I/O costs > 25% of total Aurora bill, switch to I/O-Optimized
- I/O-Optimized eliminates per-I/O charges but increases instance and storage cost by ~30%
- Check with `cost-check` skill for specific workload analysis
