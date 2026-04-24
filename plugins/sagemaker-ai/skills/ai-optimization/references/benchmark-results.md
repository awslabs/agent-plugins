# Benchmark Results Download

Generate a notebook cell that downloads and displays benchmark results. The output is stored as an `output.tar.gz` archive — the primary metrics file is `profile_export_aiperf.json`.

```python
import io
import json
import tarfile
from urllib.parse import urlparse

import boto3

# sm client is defined in a prior cell (Step 3)
result = sm.describe_ai_benchmark_job(AIBenchmarkJobName="my-benchmark-job")
s3_output = result["OutputConfig"]["S3OutputLocation"]

print(f"Job status: {result['AIBenchmarkJobStatus']}")
print(f"Results location: {s3_output}")

# Download the output.tar.gz archive from S3
s3 = boto3.client("s3")
parsed = urlparse(s3_output)
bucket = parsed.netloc
prefix = parsed.path.lstrip("/")

try:
    # Find the tar.gz file
    objects = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    tar_key = None
    for obj in objects.get("Contents", []):
        if obj["Key"].endswith(".tar.gz"):
            tar_key = obj["Key"]
            break

    if not tar_key:
        raise FileNotFoundError(f"No tar.gz archive found at s3://{bucket}/{prefix}")

    # Download and extract the primary metrics file
    tar_bytes = s3.get_object(Bucket=bucket, Key=tar_key)["Body"].read()

    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:gz") as tar:
        print(f"Archive contents: {tar.getnames()}")

        metrics_data = None
        for member in tar.getmembers():
            if "profile_export_aiperf.json" in member.name:
                f = tar.extractfile(member)
                if f:
                    metrics_data = json.loads(f.read().decode("utf-8"))
                    break

    if not metrics_data:
        raise FileNotFoundError("profile_export_aiperf.json not found in archive")

    # Display key metrics as a summary table
    summary_metrics = [
        "time_to_first_token", "inter_token_latency",
        "output_token_throughput", "request_throughput",
        "request_latency",
    ]
    rows = []
    for key in summary_metrics:
        metric = metrics_data.get(key)
        if isinstance(metric, dict) and "unit" in metric:
            rows.append({
                "Metric": key,
                "p50": metric.get("p50"),
                "p90": metric.get("p90"),
                "p99": metric.get("p99"),
                "avg": metric.get("avg"),
                "Unit": metric.get("unit"),
            })
    if rows:
        # Format as aligned text table (no pandas dependency)
        header = f"{'Metric':<30} {'p50':>10} {'p90':>10} {'p99':>10} {'avg':>10} {'Unit':<15}"
        print(header)
        print("-" * len(header))
        for r in rows:
            print(f"{r['Metric']:<30} {r['p50'] or '':>10} {r['p90'] or '':>10} "
                  f"{r['p99'] or '':>10} {r['avg'] or '':>10} {r['Unit']:<15}")
    else:
        print("No recognized metrics found in profile_export_aiperf.json")

except FileNotFoundError as e:
    print(f"Results not available: {e}")
except Exception as e:
    print(f"Error downloading results: {e}")
    print("Check that the IAM role has s3:GetObject and s3:ListBucket permissions.")
```
