# Non-AWS Providers and Examples

## Kubernetes Categories

| Category | Common Icons |
|----------|-------------|
| `k8s.compute` | Pod, Deployment, StatefulSet, ReplicaSet, DaemonSet, Job |
| `k8s.network` | Service, Ingress, NetworkPolicy |
| `k8s.storage` | PV, PVC, StorageClass |
| `k8s.controlplane` | APIServer, Scheduler, ControllerManager |
| `k8s.clusterconfig` | HPA, Namespace, Quota |
| `k8s.rbac` | Role, RoleBinding, ClusterRole |

## On-Premises Categories

| Category | Common Icons |
|----------|-------------|
| `onprem.compute` | Server |
| `onprem.database` | PostgreSQL, MySQL, MongoDB, Cassandra |
| `onprem.container` | Docker |
| `onprem.ci` | Jenkins, GitlabCI, GithubActions |
| `onprem.monitoring` | Prometheus, Grafana, Datadog |
| `onprem.logging` | Fluentd, Loki |
| `onprem.queue` | Kafka, RabbitMQ, Celery |
| `onprem.network` | Nginx, HAProxy, Traefik |
| `onprem.inmemory` | Redis, Memcached |
| `onprem.vcs` | Git, Github, Gitlab |
| `onprem.iac` | Terraform, Ansible |

## Flowchart Shapes

```python
from diagrams.programming.flowchart import (
    Action,          # Rectangle -- process step
    Decision,        # Diamond -- yes/no branch
    InputOutput,     # Parallelogram -- data input/output
    Predefined,      # Double-border rectangle -- predefined process
    Delay,           # Half-oval -- wait/delay
)
```

## Example: Kubernetes Exposed Pod

```python
from diagrams import Diagram
from diagrams.k8s.compute import Deployment, Pod, ReplicaSet
from diagrams.k8s.clusterconfig import HPA
from diagrams.k8s.network import Ingress, Service

with Diagram("Exposed Pod", show=False, filename="generated-diagrams/k8s-exposed"):
    net = Ingress("domain.com") >> Service("svc")
    net >> [Pod("pod1"), Pod("pod2"), Pod("pod3")] << ReplicaSet("rs") << Deployment("dp") << HPA("hpa")
```

## Example: Order Processing Flow

```python
from diagrams import Diagram
from diagrams.programming.flowchart import Action, Decision, Delay, InputOutput, Predefined

with Diagram("Order Processing", show=False, filename="generated-diagrams/flow"):
    start = Predefined("Start")
    order = InputOutput("Order Received")
    check = Decision("In Stock?")
    process = Action("Process Order")
    wait = Delay("Backorder")
    ship = Action("Ship Order")
    end = Predefined("End")
    start >> order >> check
    check >> process >> ship >> end
    check >> wait >> process
```

## Example: On-Premises with Colored Edges

```python
from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.logging import Fluentd
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.network import Nginx
from diagrams.onprem.queue import Kafka

with Diagram("On-Prem Service", show=False, filename="generated-diagrams/onprem"):
    ingress = Nginx("ingress")
    metrics = Prometheus("metric")
    metrics << Edge(color="firebrick", style="dashed") << Grafana("monitoring")
    with Cluster("Service Cluster"):
        grpcsvc = [Server("grpc1"), Server("grpc2"), Server("grpc3")]
    with Cluster("Sessions HA"):
        primary = Redis("session")
        primary - Edge(color="brown", style="dashed") - Redis("replica")
        grpcsvc >> Edge(color="brown") >> primary
    with Cluster("Database HA"):
        db = PostgreSQL("users")
        db - Edge(color="brown", style="dotted") - PostgreSQL("replica")
        grpcsvc >> Edge(color="black") >> db
    aggregator = Fluentd("logging")
    aggregator >> Edge(label="parse") >> Kafka("stream")
    ingress >> Edge(color="darkgreen") << grpcsvc >> Edge(color="darkorange") >> aggregator
```

## Example: Custom Icons

```python
from diagrams import Diagram, Cluster
from diagrams.aws.database import Aurora
from diagrams.custom import Custom
from diagrams.k8s.compute import Pod

# Place icon files in your project directory beforehand.
# Download from official sources and save locally, e.g.:
#   curl -o icons/rabbitmq.png https://rabbitmq.com/img/rabbitmq-logo.png

with Diagram("Custom Icons", show=False, filename="generated-diagrams/custom"):
    with Cluster("Consumers"):
        consumers = [Pod("worker"), Pod("worker"), Pod("worker")]
    queue = Custom("Message queue", "icons/rabbitmq.png")
    queue >> consumers >> Aurora("Database")
```
