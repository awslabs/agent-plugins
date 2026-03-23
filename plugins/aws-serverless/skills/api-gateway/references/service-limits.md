# Service Limits and Quotas

**Important**: Values listed here are **default quotas**; many are adjustable via AWS Support or Service Quotas console. Do not use default values for architectural decisions without first checking with your AWS account team for current limits and increase possibilities. Consult the [latest API Gateway quotas page](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html) for up-to-date values as they change over time.

## REST API Limits

| Resource                                 | Default Limit                                    | Adjustable                 |
| ---------------------------------------- | ------------------------------------------------ | -------------------------- |
| Regional APIs per region                 | 600                                              | Yes                        |
| Edge-optimized APIs per region           | 120                                              | Yes                        |
| Private APIs per region                  | 600                                              | Yes                        |
| Resources per API                        | 300                                              | Yes                        |
| Stages per API                           | 10                                               | No                         |
| Stage variables per stage                | 100                                              | No                         |
| Authorizers per API                      | 10                                               | Yes                        |
| API keys per region                      | 10,000                                           | Yes                        |
| Usage plans per region                   | 300                                              | Yes                        |
| VPC links per region                     | 20                                               | Yes                        |
| Custom domains (public) per region       | 120                                              | Yes                        |
| Custom domains (private) per region      | 50                                               | Yes                        |
| API mappings per domain                  | 200                                              | No                         |
| Base path max length                     | 300 chars                                        | No                         |
| **Payload size**                         | **10 MB**                                        | **No**                     |
| **Integration timeout**                  | **50ms - 29s (up to 300s for Regional/Private)** | **Yes (Regional/Private)** |
| Mapping template size                    | 300 KB                                           | No                         |
| `#foreach` iterations                    | 1,000                                            | No                         |
| Access log template                      | 3 KB                                             | No                         |
| Header values total                      | 10,240 bytes                                     | No                         |
| Header values total (private)            | 8,000 bytes                                      | No                         |
| Cache TTL                                | 0 - 3,600s                                       | No                         |
| Cached response max                      | 1,048,576 bytes (1 MB)                           | No                         |
| Method ARN length                        | 1,600 bytes                                      | No                         |
| Method-level throttle settings per stage | 20                                               | No                         |
| Model size                               | 400 KB                                           | No                         |
| mTLS truststore                          | 1,000 certs / 1 MB                               | No                         |
| Idle connection timeout                  | 310s                                             | No                         |
| API definition import size               | 6 MB                                             | No                         |
| Lambda authorizer result TTL             | 0 - 3,600s (default 300s)                        | No                         |

## HTTP API Limits

| Resource                     | Default Limit        | Adjustable |
| ---------------------------- | -------------------- | ---------- |
| APIs per region              | 600                  | Yes        |
| Routes per API               | 300                  | No         |
| Integrations per API         | 300                  | No         |
| **Integration timeout**      | **30s (hard limit)** | **No**     |
| **Payload size**             | **10 MB**            | **No**     |
| Stages per API               | 10                   | Yes        |
| Custom domains per region    | 120                  | Yes        |
| Access log entry max         | 1 MB                 | No         |
| Authorizers per API          | 10                   | Yes        |
| Audiences per JWT authorizer | 50                   | No         |
| Scopes per route             | 10                   | No         |
| JWKS endpoint timeout        | 1,500ms              | No         |
| Lambda authorizer timeout    | 10,000ms             | No         |
| VPC links per region         | 10                   | Yes        |

## WebSocket API Limits

| Resource              | Default Limit | Adjustable |
| --------------------- | ------------- | ---------- |
| Frame size            | 32 KB         | No         |
| Message payload       | 128 KB        | No         |
| Connection duration   | 2 hours       | No         |
| Idle timeout          | 10 minutes    | No         |
| New connections rate  | 500/s         | Yes        |
| Routes per API        | 300           | No         |
| Authorizer result max | 8 KB          | No         |
| Integration timeout   | 29s           | No         |

## Account-Level Throttling

| Resource          | Default Limit | Adjustable |
| ----------------- | ------------- | ---------- |
| Steady-state rate | 10,000 rps    | Yes        |
| Burst capacity    | 5,000         | Yes        |

These apply across all REST APIs, HTTP APIs, WebSocket APIs, and WebSocket callback APIs in a region ([shared quota](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html)). Lower defaults apply in opt-in and newer regions (2,500 rps / 1,250 burst): af-south-1, eu-south-1, ap-southeast-3, me-south-1, ap-south-2, ap-southeast-4, eu-south-2, eu-central-2, il-central-1, ca-west-1, ap-southeast-5, ap-southeast-7, mx-central-1.

## Management API Rate Limits

| Resource                   | Limit             |
| -------------------------- | ----------------- |
| Total management API calls | 10 rps / 40 burst |
| Custom domain deletion     | 1 per 30 seconds  |

## Cache Sizes (REST API)

| Size    | Monthly Cost (approximate) |
| ------- | -------------------------- |
| 0.5 GB  | Low                        |
| 1.6 GB  |                            |
| 6.1 GB  |                            |
| 13.5 GB |                            |
| 28.4 GB |                            |
| 58.2 GB |                            |
| 118 GB  |                            |
| 237 GB  | High                       |

## Reserved Paths

- `/ping` and `/sping` are reserved by API Gateway. Do not use for API resources

## Gateway Response Types

| Response Type                  | Default Status | Customizable |
| ------------------------------ | -------------- | ------------ |
| ACCESS_DENIED                  | 403            | Yes          |
| API_CONFIGURATION_ERROR        | 500            | Yes          |
| AUTHORIZER_CONFIGURATION_ERROR | 500            | Yes          |
| AUTHORIZER_FAILURE             | 500            | Yes          |
| BAD_REQUEST_PARAMETERS         | 400            | Yes          |
| BAD_REQUEST_BODY               | 400            | Yes          |
| DEFAULT_4XX                    | Varies         | Yes          |
| DEFAULT_5XX                    | Varies         | Yes          |
| EXPIRED_TOKEN                  | 403            | Yes          |
| INTEGRATION_FAILURE            | 504            | Yes          |
| INTEGRATION_TIMEOUT            | 504            | Yes          |
| INVALID_API_KEY                | 403            | Yes          |
| INVALID_SIGNATURE              | 403            | Yes          |
| MISSING_AUTHENTICATION_TOKEN   | 403            | Yes          |
| QUOTA_EXCEEDED                 | 429            | Yes          |
| **REQUEST_TOO_LARGE**          | **413**        | **No**       |
| RESOURCE_NOT_FOUND             | 404            | Yes          |
| THROTTLED                      | 429            | Yes          |
| UNAUTHORIZED                   | 401            | Yes          |
| WAF_FILTERED                   | 403            | Yes          |

**Note**: REQUEST_TOO_LARGE (413) is the only gateway response that CANNOT be customized. Use DEFAULT_4XX for CORS headers on this response.

## Feature Availability Matrix

| Feature                  | REST API              | HTTP API              | WebSocket                  |
| ------------------------ | --------------------- | --------------------- | -------------------------- |
| Caching                  | Yes                   | No                    | No                         |
| Usage plans / API keys   | Yes                   | No                    | No                         |
| AWS WAF                  | Yes                   | No                    | No                         |
| Request validation       | Yes                   | No                    | No                         |
| VTL mapping templates    | Yes                   | No                    | Yes                        |
| Resource policies        | Yes                   | No                    | No                         |
| Private endpoints        | Yes                   | No                    | No                         |
| mTLS                     | Yes (custom domain)   | Yes (custom domain)   | Via CloudFront viewer mTLS |
| JWT authorizer           | No                    | Yes                   | No                         |
| Cognito authorizer       | Yes                   | Use JWT               | No                         |
| Lambda authorizer        | Yes (TOKEN + REQUEST) | Yes (REQUEST, simple) | Yes ($connect)             |
| Canary deployments       | Yes                   | No                    | No                         |
| Response streaming       | Yes                   | No                    | No                         |
| Automatic deployments    | No                    | Yes                   | No                         |
| X-Ray tracing            | Yes                   | No                    | No                         |
| Execution logging        | Yes                   | No                    | Yes                        |
| Access logging           | Yes                   | Yes                   | Yes                        |
| Custom gateway responses | Yes                   | No                    | No                         |
| SDK generation           | Yes                   | No                    | No                         |
| API documentation        | Yes                   | No                    | No                         |
| Client certificates      | Yes                   | No                    | No                         |
