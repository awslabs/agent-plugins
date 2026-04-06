# IoT Security and Provisioning

## X.509 Certificate Management

### Certificate Hierarchy

```
AWS Private CA (Root CA)
  └── Subordinate CA (per environment or region)
       └── Device Certificates (one per device)
```

Use a subordinate CA per environment (prod, staging) so you can revoke an entire environment's CA without affecting others.

### Register a CA Certificate

```bash
# 1. Generate the CA certificate (or use AWS Private CA)
aws iot register-ca-certificate \
  --ca-certificate file://ca-cert.pem \
  --verification-certificate file://verification-cert.pem \
  --set-as-active \
  --allow-auto-registration
```

The `--allow-auto-registration` flag enables JITP: any device presenting a certificate signed by this CA will be automatically registered on first connection.

### Register a Device Certificate

```bash
# Register and activate a specific device certificate
aws iot register-certificate \
  --certificate-pem file://device-cert.pem \
  --ca-certificate-pem file://ca-cert.pem \
  --set-as-active

# Attach the certificate to a thing
aws iot attach-thing-principal \
  --thing-name "sensor-001" \
  --principal "arn:aws:iot:REGION:ACCOUNT:cert/CERT_ID"

# Attach an IoT policy to the certificate
aws iot attach-policy \
  --policy-name "sensor-telemetry-policy" \
  --target "arn:aws:iot:REGION:ACCOUNT:cert/CERT_ID"
```

### Certificate Rotation

Rotate certificates before expiry using IoT Jobs. The process:

1. Generate new certificate (via AWS Private CA or your PKI)
2. Create an IoT Job that pushes the new certificate to the device
3. Device stores new certificate, acknowledges the job
4. Lambda function registers the new certificate and deactivates the old one
5. Device reconnects with the new certificate
6. After confirmation, revoke and delete the old certificate

```bash
# Deactivate old certificate
aws iot update-certificate \
  --certificate-id OLD_CERT_ID \
  --new-status INACTIVE

# Delete after grace period
aws iot delete-certificate \
  --certificate-id OLD_CERT_ID \
  --force-delete
```

### Certificate Revocation

```bash
# Revoke a compromised certificate immediately
aws iot update-certificate \
  --certificate-id COMPROMISED_CERT_ID \
  --new-status REVOKED

# Move the device to a quarantine thing group
aws iot add-thing-to-thing-group \
  --thing-name "compromised-device" \
  --thing-group-name "quarantine"
```

The quarantine thing group should have a group policy that denies all actions except connecting and receiving new certificates (for remediation).

## Fleet Provisioning Templates

### Just-in-Time Provisioning (JITP) Template

Register this template with your CA certificate. When a device connects with a certificate signed by this CA, IoT Core auto-creates the thing and attaches the policy.

```json
{
  "templateBody": {
    "Parameters": {
      "AWS::IoT::Certificate::CommonName": { "Type": "String" },
      "AWS::IoT::Certificate::Id": { "Type": "String" }
    },
    "Resources": {
      "thing": {
        "Type": "AWS::IoT::Thing",
        "Properties": {
          "ThingName": { "Ref": "AWS::IoT::Certificate::CommonName" },
          "ThingGroups": ["auto-provisioned"],
          "AttributePayload": {
            "provisioning_method": "JITP",
            "provisioned_at": "{{timestamp}}"
          }
        }
      },
      "certificate": {
        "Type": "AWS::IoT::Certificate",
        "Properties": {
          "CertificateId": { "Ref": "AWS::IoT::Certificate::Id" },
          "Status": "ACTIVE"
        }
      },
      "policy": {
        "Type": "AWS::IoT::Policy",
        "Properties": {
          "PolicyName": "device-scoped-policy"
        }
      }
    }
  }
}
```

### Fleet Provisioning by Claim Template

For devices without pre-installed unique certificates. The device uses a shared claim certificate to request a unique identity.

```json
{
  "Parameters": {
    "SerialNumber": { "Type": "String" },
    "DeviceType": { "Type": "String" }
  },
  "Resources": {
    "thing": {
      "Type": "AWS::IoT::Thing",
      "Properties": {
        "ThingName": { "Fn::Join": ["-", [{ "Ref": "DeviceType" }, { "Ref": "SerialNumber" }]] },
        "ThingGroups": [{ "Ref": "DeviceType" }],
        "AttributePayload": {
          "serial_number": { "Ref": "SerialNumber" },
          "device_type": { "Ref": "DeviceType" }
        }
      },
      "OverrideSettings": {
        "ThingGroups": "MERGE"
      }
    },
    "certificate": {
      "Type": "AWS::IoT::Certificate",
      "Properties": {
        "CertificateId": { "Ref": "AWS::IoT::Certificate::Id" },
        "Status": "ACTIVE"
      }
    },
    "policy": {
      "Type": "AWS::IoT::Policy",
      "Properties": {
        "PolicyName": "device-scoped-policy"
      }
    }
  }
}
```

### Create the Provisioning Template

```bash
# Create the provisioning template
aws iot create-provisioning-template \
  --template-name "sensor-provisioning" \
  --template-body file://provisioning-template.json \
  --provisioning-role-arn "arn:aws:iam::ACCOUNT:role/iot-provisioning-role" \
  --enabled \
  --pre-provisioning-hook '{
    "targetArn": "arn:aws:lambda:REGION:ACCOUNT:function:validate-device",
    "payloadVersion": "2020-04-01"
  }'
```

### Pre-Provisioning Hook Lambda

This Lambda validates the device identity before allowing provisioning. Critical for fleet provisioning by claim to prevent unauthorized device registration.

```python
import json
import boto3

dynamodb = boto3.resource('dynamodb')
allow_list = dynamodb.Table('device-allow-list')

def handler(event, context):
    serial_number = event['parameters']['SerialNumber']
    device_type = event['parameters']['DeviceType']

    # Check if the device serial number is in the allow list
    response = allow_list.get_item(
        Key={'serial_number': serial_number}
    )

    if 'Item' not in response:
        return {
            'allowProvisioning': False
        }

    # Verify the device type matches the expected type
    if response['Item'].get('device_type') != device_type:
        return {
            'allowProvisioning': False
        }

    return {
        'allowProvisioning': True
    }
```

### Claim Certificate Policy (Minimal)

The claim certificate should only have permission to connect and call the fleet provisioning APIs. Nothing else.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["iot:Publish", "iot:Receive"],
      "Resource": [
        "arn:aws:iot:REGION:ACCOUNT:topic/$aws/certificates/create/*",
        "arn:aws:iot:REGION:ACCOUNT:topic/$aws/provisioning-templates/sensor-provisioning/provision/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": [
        "arn:aws:iot:REGION:ACCOUNT:topicfilter/$aws/certificates/create/*",
        "arn:aws:iot:REGION:ACCOUNT:topicfilter/$aws/provisioning-templates/sensor-provisioning/provision/*"
      ]
    }
  ]
}
```

## IoT Policies with Variables

### Per-Device Scoped Policy (Production Default)

This policy uses `${iot:Connection.Thing.ThingName}` to dynamically scope permissions to the connected device's own resources.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:REGION:ACCOUNT:client/${iot:Connection.Thing.ThingName}",
      "Condition": {
        "Bool": { "iot:Connection.Thing.IsAttached": "true" }
      }
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/${iot:Connection.Thing.ThingName}/telemetry",
        "arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/${iot:Connection.Thing.ThingName}/alerts",
        "arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/${iot:Connection.Thing.ThingName}/status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": [
        "arn:aws:iot:REGION:ACCOUNT:topicfilter/acme/prod/*/${iot:Connection.Thing.ThingName}/commands",
        "arn:aws:iot:REGION:ACCOUNT:topicfilter/$aws/things/${iot:Connection.Thing.ThingName}/shadow/*",
        "arn:aws:iot:REGION:ACCOUNT:topicfilter/$aws/things/${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": [
        "arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/${iot:Connection.Thing.ThingName}/commands",
        "arn:aws:iot:REGION:ACCOUNT:topic/$aws/things/${iot:Connection.Thing.ThingName}/shadow/*",
        "arn:aws:iot:REGION:ACCOUNT:topic/$aws/things/${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iot:GetThingShadow",
        "iot:UpdateThingShadow"
      ],
      "Resource": "arn:aws:iot:REGION:ACCOUNT:thing/${iot:Connection.Thing.ThingName}"
    }
  ]
}
```

### Key Policy Variables

| Variable | Value | Use For |
|---|---|---|
| `${iot:Connection.Thing.ThingName}` | Thing name of the connected device | Scoping topics, shadows, and jobs to the connected device |
| `${iot:Connection.Thing.IsAttached}` | `true` if cert is attached to a thing | Requiring certificate-to-thing binding before allowing connect |
| `${iot:Connection.Thing.Attributes[key]}` | Thing attribute value | Scoping by device type, location, or other custom attributes |
| `${iot:ClientId}` | MQTT client ID | Enforcing client ID matches thing name |

### Policy Best Practices

- Always require `iot:Connection.Thing.IsAttached` condition on the Connect action. Without it, a certificate not attached to any thing can still connect.
- Separate Publish and Subscribe/Receive permissions. Devices should publish to telemetry/alerts topics but only subscribe to commands/shadow/jobs topics.
- Never use wildcards in the account or region segments of ARNs.
- Test policies using the IoT Policy Simulator before deploying to production devices.

## Custom Authorizer Setup

Use custom authorizers when devices authenticate with tokens instead of X.509 certificates (legacy protocols, shared infrastructure, third-party devices).

### Create the Authorizer Lambda

```python
import json

def handler(event, context):
    token = event.get('token', '')
    # event also contains: protocolData, connectionMetadata

    # Validate the token (check against your auth system)
    if not validate_token(token):
        raise Exception('Unauthorized')

    # Extract device identity from token
    device_id = extract_device_id(token)

    return {
        'isAuthenticated': True,
        'principalId': device_id,
        'disconnectAfterInSeconds': 86400,
        'refreshAfterInSeconds': 3600,
        'policyDocuments': [
            json.dumps({
                'Version': '2012-10-17',
                'Statement': [
                    {
                        'Effect': 'Allow',
                        'Action': 'iot:Connect',
                        'Resource': f'arn:aws:iot:REGION:ACCOUNT:client/{device_id}'
                    },
                    {
                        'Effect': 'Allow',
                        'Action': ['iot:Publish', 'iot:Subscribe', 'iot:Receive'],
                        'Resource': f'arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/{device_id}/*'
                    }
                ]
            })
        ]
    }

def validate_token(token):
    # Implement your token validation logic
    # Check JWT signature, expiry, issuer, etc.
    pass

def extract_device_id(token):
    # Extract device identity from the token payload
    pass
```

### Register the Custom Authorizer

```bash
# Create the authorizer
aws iot create-authorizer \
  --authorizer-name "token-authorizer" \
  --authorizer-function-arn "arn:aws:lambda:REGION:ACCOUNT:function:iot-custom-auth" \
  --token-key-name "x-auth-token" \
  --token-signing-public-keys "FirstKey=file://public-key.pem" \
  --signing-disabled \
  --status ACTIVE

# Grant IoT permission to invoke the Lambda
aws lambda add-permission \
  --function-name iot-custom-auth \
  --principal iot.amazonaws.com \
  --statement-id iot-invoke \
  --action lambda:InvokeFunction \
  --source-arn "arn:aws:iot:REGION:ACCOUNT:authorizer/token-authorizer"
```

### Custom Authorizer Caching

- Enable caching to reduce Lambda invocations and latency. Set `refreshAfterInSeconds` in the Lambda response.
- Cache TTL should balance security (shorter = faster revocation) and cost (longer = fewer Lambda invocations).
- For production: 300-3600 seconds is typical. For high-security environments: 60-300 seconds.

## Device Defender Configuration

### Enable Audit

```bash
# Create an audit role
# (IAM role with iot:DescribeThing, iot:ListThings, etc.)

# Enable audit checks
aws iot update-account-audit-configuration \
  --audit-check-configurations '{
    "DEVICE_CERTIFICATE_SHARED_CHECK": { "enabled": true },
    "CA_CERTIFICATE_EXPIRING_CHECK": { "enabled": true },
    "IOT_POLICY_OVERLY_PERMISSIVE_CHECK": { "enabled": true },
    "LOGGING_DISABLED_CHECK": { "enabled": true },
    "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK": { "enabled": true },
    "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": { "enabled": true }
  }' \
  --role-arn "arn:aws:iam::ACCOUNT:role/iot-device-defender-audit-role"

# Schedule weekly audit
aws iot create-scheduled-audit \
  --scheduled-audit-name "weekly-security-audit" \
  --frequency WEEKLY \
  --day-of-week MON \
  --target-check-names \
    DEVICE_CERTIFICATE_SHARED_CHECK \
    CA_CERTIFICATE_EXPIRING_CHECK \
    IOT_POLICY_OVERLY_PERMISSIVE_CHECK \
    LOGGING_DISABLED_CHECK
```

### Enable Detect (Anomaly Detection)

```bash
# Create a security profile for all devices
aws iot create-security-profile \
  --security-profile-name "baseline-behavior" \
  --behaviors '[
    {
      "name": "message-volume",
      "metric": { "name": "aws:num-messages-sent" },
      "criteria": {
        "comparisonOperator": "less-than",
        "value": { "count": 1000 },
        "durationInSeconds": 300
      }
    },
    {
      "name": "auth-failures",
      "metric": { "name": "aws:num-authorization-failures" },
      "criteria": {
        "comparisonOperator": "less-than",
        "value": { "count": 5 },
        "durationInSeconds": 300
      }
    },
    {
      "name": "connection-attempts",
      "metric": { "name": "aws:num-connection-attempts" },
      "criteria": {
        "comparisonOperator": "less-than",
        "value": { "count": 10 },
        "durationInSeconds": 300
      }
    }
  ]' \
  --alert-targets '{
    "SNS": {
      "alertTargetArn": "arn:aws:sns:REGION:ACCOUNT:iot-security-alerts",
      "roleArn": "arn:aws:iam::ACCOUNT:role/iot-defender-sns-role"
    }
  }'

# Attach the security profile to all things
aws iot attach-security-profile \
  --security-profile-name "baseline-behavior" \
  --security-profile-target-arn "arn:aws:iot:REGION:ACCOUNT:all/things"
```

### Mitigation Actions

```bash
# Create a mitigation action to quarantine compromised devices
aws iot create-mitigation-action \
  --action-name "quarantine-device" \
  --action-params '{
    "addThingsToThingGroupParams": {
      "thingGroupNames": ["quarantine"],
      "overrideDynamicGroups": true
    }
  }' \
  --role-arn "arn:aws:iam::ACCOUNT:role/iot-mitigation-role"
```

The quarantine thing group should have a restrictive group policy that:
1. Allows only `iot:Connect` (so the device can be reached for remediation)
2. Allows subscribe/receive only on the jobs topic (to receive certificate rotation or firmware update)
3. Denies all publish except to a quarantine status topic
