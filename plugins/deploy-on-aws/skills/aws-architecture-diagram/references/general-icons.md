# General Architecture Icons

When the architecture includes non-AWS services (on-premises, third-party, open-source, or platform-native), use these mappings. Same 120x120 container + 48x48 icon pattern as AWS services. Category tint colors match the AWS palette so mixed diagrams look consistent.

The icon is generic — **the container label and service name are critical** for identification.

## Technology to Shape Mapping

### Databases

| Technology                           | resIcon shape      | Category (tint / stroke)     |
| ------------------------------------ | ------------------ | ---------------------------- |
| PostgreSQL, MySQL, MariaDB, SQLite   | `generic_database` | Database (#F5E6F7 / #C925D1) |
| MongoDB, Redis, Elasticsearch, Neo4j | `generic_database` | Database (#F5E6F7 / #C925D1) |

### Compute and Runtime

| Technology                      | resIcon shape         | Category (tint / stroke)    |
| ------------------------------- | --------------------- | --------------------------- |
| Docker, Kubernetes, VMs         | `container_1`         | Compute (#FFF2E8 / #ED7100) |
| On-premises servers, bare metal | `traditional_server`  | Compute (#FFF2E8 / #ED7100) |
| macOS, iOS, Android native app  | `mobile_client`       | Compute (#FFF2E8 / #ED7100) |
| Desktop application, CLI tool   | `generic_application` | Compute (#FFF2E8 / #ED7100) |
| Web server (nginx, Apache)      | `traditional_server`  | Compute (#FFF2E8 / #ED7100) |

### External Services and APIs

| Technology                 | resIcon shape         | Category (tint / stroke)            |
| -------------------------- | --------------------- | ----------------------------------- |
| GitHub, GitLab, Bitbucket  | `internet`            | Networking (#EDE7F6 / #8C4FFF)      |
| REST/GraphQL API endpoints | `internet`            | Networking (#EDE7F6 / #8C4FFF)      |
| Stripe, Twilio, SendGrid   | `generic_application` | App Integration (#FCE4EC / #E7157B) |
| CDN (Cloudflare, Fastly)   | `internet`            | Networking (#EDE7F6 / #8C4FFF)      |
| DNS providers              | `internet`            | Networking (#EDE7F6 / #8C4FFF)      |

### AI and ML

| Technology                     | resIcon shape         | Category (tint / stroke)  |
| ------------------------------ | --------------------- | ------------------------- |
| HuggingFace, OpenAI, Anthropic | `generic_application` | AI/ML (#E0F2F1 / #01A88D) |
| CoreML, TensorFlow, PyTorch    | `generic_application` | AI/ML (#E0F2F1 / #01A88D) |
| ML model files, ONNX runtime   | `generic_application` | AI/ML (#E0F2F1 / #01A88D) |

### Storage

| Technology                   | resIcon shape         | Category (tint / stroke)    |
| ---------------------------- | --------------------- | --------------------------- |
| Local filesystem, NFS, CIFS  | `generic_application` | Storage (#E8F5E9 / #3F8624) |
| Object storage (MinIO, Ceph) | `generic_application` | Storage (#E8F5E9 / #3F8624) |

### Messaging and Streaming

| Technology                  | resIcon shape         | Category (tint / stroke)            |
| --------------------------- | --------------------- | ----------------------------------- |
| Kafka, RabbitMQ, NATS, MQTT | `generic_application` | App Integration (#FCE4EC / #E7157B) |
| WebSocket, gRPC, pub/sub    | `generic_application` | App Integration (#FCE4EC / #E7157B) |

### Security and Auth

| Technology                  | resIcon shape         | Category (tint / stroke)     |
| --------------------------- | --------------------- | ---------------------------- |
| OAuth, OIDC, SAML, LDAP     | `generic_application` | Security (#FFEBEE / #DD344C) |
| Vault (HashiCorp), KeyCloak | `generic_application` | Security (#FFEBEE / #DD344C) |

### Monitoring and Observability

| Technology                   | resIcon shape         | Category (tint / stroke)       |
| ---------------------------- | --------------------- | ------------------------------ |
| Prometheus, Grafana, Datadog | `generic_application` | Management (#FCE4EC / #E7157B) |
| ELK stack, Splunk, PagerDuty | `generic_application` | Management (#FCE4EC / #E7157B) |

### External Actors (outside the system boundary)

| Actor                 | resIcon shape           | Container style                                       |
| --------------------- | ----------------------- | ----------------------------------------------------- |
| End users / people    | `users`                 | fillColor=#f5f5f5, stroke=light-dark(#666666,#D4D4D4) |
| Mobile users          | `mobile_client`         | fillColor=#f5f5f5, stroke=light-dark(#666666,#D4D4D4) |
| IoT devices / sensors | `sensor`                | fillColor=#f5f5f5, stroke=light-dark(#666666,#D4D4D4) |
| Corporate data center | `corporate_data_center` | fillColor=#f5f5f5, stroke=light-dark(#666666,#D4D4D4) |

## Boundary Groups for Non-AWS

For non-AWS architectures, replace the AWS Cloud boundary group with a generic system boundary:

- Use `group_corporate_data_center` style for on-premises boundaries
- Use a plain `group` style with dashed border for logical boundaries
- Keep the same `container=0` pattern for decorative region/zone groups
