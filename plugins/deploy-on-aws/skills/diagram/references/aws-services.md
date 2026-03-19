# AWS Services and Examples

## AWS Service Categories

| Category      | Import Path                | Common Icons                                        |
| ------------- | -------------------------- | --------------------------------------------------- |
| `analytics`   | `diagrams.aws.analytics`   | Athena, EMR, Glue, Kinesis, Redshift, Quicksight    |
| `compute`     | `diagrams.aws.compute`     | EC2, Lambda, ECS, EKS, Fargate, Batch               |
| `database`    | `diagrams.aws.database`    | RDS, Aurora, Dynamodb, ElastiCache, Neptune         |
| `integration` | `diagrams.aws.integration` | SQS, SNS, StepFunctions, Eventbridge, MQ            |
| `management`  | `diagrams.aws.management`  | Cloudwatch, Cloudformation, SystemsManager          |
| `ml`          | `diagrams.aws.ml`          | Sagemaker, Rekognition, Comprehend, Bedrock         |
| `network`     | `diagrams.aws.network`     | VPC, ELB, ALB, NLB, CloudFront, Route53, APIGateway |
| `security`    | `diagrams.aws.security`    | IAM, Cognito, WAF, KMS, Shield, SecretsManager      |
| `storage`     | `diagrams.aws.storage`     | S3, EBS, EFS, FSx, Backup                           |
| `general`     | `diagrams.aws.general`     | User, Users, Client, InternetGateway                |

Other categories: `ar`, `blockchain`, `business`, `cost`, `devtools`, `enablement`, `enduser`, `engagement`, `game`, `iot`, `media`, `migration`, `mobile`, `quantum`, `robotics`, `satellite`.

## Example: Basic Web Service

```python
from diagrams import Diagram
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB

with Diagram("Web Service", show=False, direction="TB", filename="generated-diagrams/aws-basic"):
    ELB("lb") >> EC2("web") >> RDS("userdb")
```

## Example: Grouped Workers

```python
from diagrams import Diagram
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB

with Diagram("Grouped Workers", show=False, direction="TB", filename="generated-diagrams/aws-workers"):
    ELB("lb") >> [EC2("w1"), EC2("w2"), EC2("w3"), EC2("w4"), EC2("w5")] >> RDS("events")
```

## Example: Clustered Web Services

```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import ECS
from diagrams.aws.database import RDS, ElastiCache
from diagrams.aws.network import ELB, Route53

with Diagram("Clustered Web Services", show=False, direction="TB", filename="generated-diagrams/aws-clustered"):
    dns = Route53("dns")
    lb = ELB("lb")
    with Cluster("Services"):
        svc_group = [ECS("web1"), ECS("web2"), ECS("web3")]
    with Cluster("DB Cluster"):
        db_primary = RDS("userdb")
        db_replica = RDS("userdb ro")
        db_primary - db_replica
    memcached = ElastiCache("memcached")
    dns >> lb >> svc_group
    svc_group >> db_primary
    svc_group >> memcached
```

## Example: Event Processing

```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import ECS, EKS, Lambda
from diagrams.aws.analytics import Redshift
from diagrams.aws.integration import SQS
from diagrams.aws.storage import S3

with Diagram("Event Processing", show=False, direction="TB", filename="generated-diagrams/aws-events"):
    source = EKS("k8s source")
    with Cluster("Event Flows"):
        with Cluster("Event Workers"):
            workers = [ECS("w1"), ECS("w2"), ECS("w3")]
        queue = SQS("event queue")
        with Cluster("Processing"):
            handlers = [Lambda("p1"), Lambda("p2"), Lambda("p3")]
    store = S3("events store")
    dw = Redshift("analytics")
    source >> workers >> queue >> handlers
    handlers >> store
    handlers >> dw
```

## Example: S3 Image Processing with Bedrock

```python
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.general import User
from diagrams.aws.ml import Bedrock
from diagrams.aws.storage import S3

with Diagram("S3 Image Processing", show=False, direction="LR", filename="generated-diagrams/aws-bedrock"):
    user = User("User")
    with Cluster("S3 Bucket"):
        input_folder = S3("Input")
        output_folder = S3("Output")
    fn = Lambda("Processor")
    bedrock = Bedrock("Claude Sonnet")
    user >> Edge(label="Upload") >> input_folder
    input_folder >> Edge(label="Trigger") >> fn
    fn >> Edge(label="Process") >> bedrock
    bedrock >> Edge(label="Result") >> fn
    fn >> Edge(label="Save") >> output_folder
```
