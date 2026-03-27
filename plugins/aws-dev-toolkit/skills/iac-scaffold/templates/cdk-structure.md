# CDK Project Structure Pattern

```
my-cdk-app/
├── bin/
│   └── app.ts                 # App entry point, stack instantiation
├── lib/
│   ├── networking-stack.ts    # VPC, subnets, security groups
│   ├── data-stack.ts          # Databases, caches, storage
│   └── compute-stack.ts       # Lambda, ECS, API Gateway
├── test/
│   └── *.test.ts              # Snapshot + fine-grained assertion tests
├── cdk.json                   # CDK config
├── tsconfig.json
├── package.json
├── Makefile                   # deploy, diff, synth, destroy shortcuts
└── README.md
```

## Key Conventions

- One stack per lifecycle boundary (networking changes rarely, compute changes often)
- Cross-stack references via stack outputs, not hardcoded ARNs
- Use `cdk-nag` in test suite for compliance
- Environment config via CDK context (`cdk.json` or `-c` flags), not env vars
- Tag all resources: `Tags.of(app).add('Project', 'my-project')`
