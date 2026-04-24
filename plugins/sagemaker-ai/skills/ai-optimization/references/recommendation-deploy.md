# Deploy from ModelPackage

Each recommendation includes a `ModelPackageArn` for direct deployment.

Generate this notebook cell:

```python
# Deploy the top recommendation
rec = resp["Recommendations"][0]
mp_arn = rec["ModelDetails"]["ModelPackageArn"]
spec_name = rec["ModelDetails"]["InferenceSpecificationName"]
instance_type = rec["DeploymentConfiguration"]["InstanceType"]

# Create model from the specific inference specification
sm.create_model(
    ModelName="my-optimized-model",
    PrimaryContainer={
        "ModelPackageName": mp_arn,
        "InferenceSpecificationName": spec_name,
    },
    ExecutionRoleArn="<ROLE_ARN>",
)

# Create endpoint config and endpoint
sm.create_endpoint_config(
    EndpointConfigName="my-optimized-epc",
    ProductionVariants=[{
        "VariantName": "AllTraffic",
        "ModelName": "my-optimized-model",
        "InstanceType": instance_type,
        "InitialInstanceCount": 1,
    }],
)

sm.create_endpoint(
    EndpointName="my-optimized-endpoint",
    EndpointConfigName="my-optimized-epc",
)
```

**Important:** Always use `InferenceSpecificationName` to select the specific recommendation's configuration. Without it, SageMaker uses the primary InferenceSpecification (a copy of the first recommendation).
