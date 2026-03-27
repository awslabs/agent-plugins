# Terraform Project Structure Pattern

```
my-terraform-project/
├── main.tf                    # Provider config, module calls
├── variables.tf               # Input variables
├── outputs.tf                 # Stack outputs
├── versions.tf                # Required providers and versions
├── backend.tf                 # Remote state config (S3 + DynamoDB)
├── modules/
│   ├── networking/            # VPC, subnets, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── compute/               # Lambda, ECS, etc.
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── Makefile                   # plan, apply, destroy per environment
└── README.md
```

## Key Conventions

- Pin provider versions in `versions.tf`
- Remote state in S3 with DynamoDB locking from day one
- One module per logical grouping, not per resource
- Use `terraform-aws-modules` for common patterns (VPC, EKS, etc.)
- `terraform fmt` and `terraform validate` in CI
- Tag all resources via `default_tags` in provider block
