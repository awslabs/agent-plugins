# Diagrams DSL Syntax Reference

## Basic Structure

```python
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import RDS
from diagrams.aws.network import ALB

with Diagram("Title", show=False, filename="generated-diagrams/name"):
    with Cluster("VPC"):
        lb = ALB("ALB")
        with Cluster("Private Subnet"):
            servers = [EC2("web1"), EC2("web2")]
        db = RDS("PostgreSQL")
    lb >> servers >> db
```

## Diagram Constructor

```python
Diagram(
    name="Diagram Title",     # Title shown on the diagram
    show=False,                # ALWAYS False -- don't open viewer
    filename="path/name",      # Output path (no .png extension)
    direction="TB",            # TB (top-bottom), LR (left-right), BT, RL
    outformat="png",           # png (default), jpg, svg, pdf
)
```

## Connections

```python
node1 >> node2 >> node3          # Left to right flow
node1 << node2                   # Right to left flow
node1 - node2                    # Bidirectional
node1 >> [node2, node3, node4]   # Fan out to multiple
node1 >> Edge(label="HTTPS", color="darkgreen", style="dashed") >> node2
```

## Clusters

```python
with Cluster("VPC"):
    with Cluster("Public Subnet"):
        lb = ALB("ALB")
    with Cluster("Private Subnet"):
        app = [EC2("app1"), EC2("app2")]
    with Cluster("Data"):
        db = RDS("db")
    lb >> app >> db
```

## Edge Styles

| Parameter | Values                                                                            |
| --------- | --------------------------------------------------------------------------------- |
| `color`   | `"darkgreen"`, `"firebrick"`, `"brown"`, `"darkorange"`, `"black"`, any CSS color |
| `style`   | `"solid"`, `"dashed"`, `"dotted"`, `"bold"`                                       |
| `label`   | Any string                                                                        |

## Provider Import Paths

| Provider    | Import Pattern                    | Example                                             |
| ----------- | --------------------------------- | --------------------------------------------------- |
| AWS         | `diagrams.aws.<category>`         | `from diagrams.aws.compute import EC2`              |
| GCP         | `diagrams.gcp.<category>`         | `from diagrams.gcp.storage import GCS`              |
| Kubernetes  | `diagrams.k8s.<category>`         | `from diagrams.k8s.compute import Pod`              |
| On-premises | `diagrams.onprem.<category>`      | `from diagrams.onprem.database import PostgreSQL`   |
| SaaS        | `diagrams.saas.<category>`        | `from diagrams.saas.chat import Slack`              |
| Programming | `diagrams.programming.<category>` | `from diagrams.programming.flowchart import Action` |
| Generic     | `diagrams.generic.<category>`     | `from diagrams.generic.compute import Rack`         |
| Custom      | `diagrams.custom`                 | `Custom("name", "icon.png")`                        |

## Common Patterns

### Fan-out / Fan-in

```python
source >> [worker1, worker2, worker3] >> sink
```

### Bidirectional with Replica

```python
primary = RDS("primary")
primary - RDS("replica")
```

### Nested Clusters

```python
with Cluster("VPC"):
    with Cluster("Public"):
        lb = ALB("ALB")
    with Cluster("Private"):
        app = [EC2("app1"), EC2("app2")]
    lb >> app
```

### Custom Nodes

```python
from diagrams.custom import Custom

# Place icon files in your project directory beforehand
custom_node = Custom("My Service", "./icons/my-service.png")
```
