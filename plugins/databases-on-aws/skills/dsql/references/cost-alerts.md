# Cost Alerts for Aurora DSQL

## Contents

- [Metric](#metric)
- [Threshold](#threshold)
- [Create the Alarm](#create-the-alarm)
- [Limits](#limits)

Alert when a cluster's hourly DPU usage nears the hourly share of a monthly budget. To explain or
reduce a cluster's cost, first compare the DPU components (`ComputeDPU`, `ReadDPU`, `WriteDPU`,
`MultiRegionWriteDPU`, `StreamDPU`) and `ClusterStorageSize` over the period, with
`get-metric-data` at `Period` 3600 or 86400 (1-minute data is kept only 15 days), adding up the DPU
datapoints; use Workflow 12 only if query activity drove it, then confirm the saving in `TotalDPU`.
See
[How billing works in Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/billing-metering.html)
and [Create a CloudWatch alarm based on a static threshold](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ConsoleAlarms.html).

If an alarm fired but nobody was notified, read its `describe-alarm-history` Action entries. An SNS
or KMS authorization error means the topic or key policy does not allow this alarm (check
`aws:SourceArn`), or the topic uses `alias/aws/sns`. No Action entry means `ActionsEnabled` is false
or the topic is not in its actions. `Successfully executed action` with no email means the
subscription is still `PendingConfirmation` or the mail was filtered.

Ask the user for the cluster ID, its Region, the monthly budget in USD, whether that budget covers
only this cluster's DPU usage or also its storage and other Regions, the customer managed KMS key
to use (or whether to create one), and the notification email. First confirm the cluster ID and
Region with `aws dsql get-cluster --region REGION --identifier CLUSTER_ID`. CloudWatch returns no
data, not an error, for a wrong ID or Region, so an alarm on it never fires and a cost comparison
reads as zero. Get `ACCOUNT_ID` from `aws sts get-caller-identity`. Then run the read-only lookups
in step 1 and the `describe-alarms` and `describe-alarms-for-metric`
in step 3. Before creating or changing anything, **MUST** show the following and wait for the
user's go-ahead:

- The account, Region and KMS key
- The topic (new or existing) and its subscribers
- Each policy change: the full merged policy; for a new key, the default policy plus the statement
- The email; it also gets an OK message when the alarm first evaluates, about a minute after
  creation, and after each breach ends
- The threshold and any existing alarm's settings

## Metric

`TotalDPU` in namespace `AWS/AuroraDSQL`, dimension `ClusterId`, is the cluster's billed DPU
usage. Storage is billed separately and is not included. **MUST** use the `Sum` statistic for DPU
metrics; use `Average` for `ClusterStorageSize`.

## Threshold

The alarm evaluates one hour at a time, so the threshold is in DPUs per hour and comes from the
part of the monthly budget, in USD, left for this cluster's DPU usage. If the budget also covers
storage, first subtract the storage cost (`ClusterStorageSize`, reported in bytes, converted to
GiB x the Region's per-GiB-month rate). A multi-Region cluster is billed for storage in each peer
Region, so when the budget also covers the other Regions, subtract each peer's storage at that
Region's rate. If it is shared across Regions, split the remainder between them; writes
replicated to peers are billed as `MultiRegionWriteDPU` in the Region where they originate, so the
writing Region needs the larger share.

```
threshold = DPU budget (USD) / per-DPU rate (USD per DPU) / 730 hours x 0.8
```

The per-DPU rate varies by Region — get it from
[Aurora DSQL pricing](https://aws.amazon.com/rds/aurora/dsql/pricing/), which lists it per million
DPUs (for example, $8 per million DPUs is 0.000008 USD per DPU).

## Create the Alarm

1. Create an encrypted SNS topic: alarm messages carry the account ID and cluster ID, so encrypt it
   at rest with SSE-KMS. The key **MUST** be customer managed, which has a monthly charge (see
   [AWS KMS pricing](https://aws.amazon.com/kms/pricing/)). The AWS managed key `alias/aws/sns`
   does not work: CloudWatch cannot use it, and the alarm fails to notify. `create-topic` returns
   an existing topic of the same name without an error unless the attributes or tags you pass
   differ from it, so first check for one. Only a `NotFound`
   error means it does not exist; stop on any other error:

   ```bash
   aws sns get-topic-attributes --region REGION \
     --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts
   aws sns list-subscriptions-by-topic --region REGION \
     --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts
   ```

   Resolve each existing key (the user's and the topic's `KmsMasterKeyId`, which may be an alias)
   with `aws kms describe-key --region REGION --key-id KEY`; use its `KeyMetadata.Arn` as
   `KMS_KEY_ARN` (`get-key-policy` rejects aliases). If `KeyManager` is not `CUSTOMER`, or the
   topic has another key or none, stop and ask the user.

   For a new key, after the go-ahead, use the `KeyMetadata.Arn` from
   `aws kms create-key --region REGION --description "DSQL cost alarms"` as `KMS_KEY_ARN`. Either
   way, add this statement to the key's policy. For this and the topic policy below, keep every
   existing statement, and skip the statement if Sid `AllowDsqlCostAlarm` already allows the alarm.
   If that Sid exists but does not, add the alarm's ARN to its `aws:SourceArn` list instead of
   replacing the pattern or adding a second statement with that Sid. For a user's own alarm found
   with `describe-alarms-for-metric`, its ARN goes in `aws:SourceArn` the same way. Write only the
   merged policy the user approved — both writes replace the whole policy:

   ```json
   {
     "Sid": "AllowDsqlCostAlarm",
     "Effect": "Allow",
     "Principal": { "Service": "cloudwatch.amazonaws.com" },
     "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
     "Resource": "*",
     "Condition": {
       "StringEquals": { "aws:SourceAccount": "ACCOUNT_ID" },
       "ArnLike": {
         "aws:SourceArn": "arn:aws:cloudwatch:REGION:ACCOUNT_ID:alarm:DSQL-Hourly-DPU-Budget-Warning-*"
       }
     }
   }
   ```

   ```bash
   P=$(mktemp)
   aws kms get-key-policy --region REGION --key-id KMS_KEY_ARN --policy-name default \
     --query Policy --output text > "$P"
   # Stop if that failed. Merge in the statement, keeping every original one; after the go-ahead:
   aws kms put-key-policy --region REGION --key-id KMS_KEY_ARN --policy-name default \
     --policy "file://$P"
   rm "$P"
   ```

   If the topic does not exist, create it and allow only these alarms to publish:

   ```bash
   aws sns create-topic --name dsql-cost-alerts --region REGION \
     --attributes KmsMasterKeyId=KMS_KEY_ARN
   aws sns set-topic-attributes --region REGION \
     --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts \
     --attribute-name Policy --attribute-value '{
       "Version": "2012-10-17",
       "Statement": [{
         "Sid": "AllowDsqlCostAlarm",
         "Effect": "Allow",
         "Principal": {"Service": "cloudwatch.amazonaws.com"},
         "Action": "sns:Publish",
         "Resource": "arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts",
         "Condition": {
           "StringEquals": {"aws:SourceAccount": "ACCOUNT_ID"},
           "ArnLike": {"aws:SourceArn": "arn:aws:cloudwatch:REGION:ACCOUNT_ID:alarm:DSQL-Hourly-DPU-Budget-Warning-*"}
         }
       }]
     }'
   ```

   If it exists, merge only this `sns:Publish` statement (not the KMS one) into its current `Policy`
   the same way and write it with `set-topic-attributes`. In both cases, subscribe the email unless
   it is already listed. The email **MUST** be an address the user confirms, and **SHOULD** be a
   monitored team or on-call list rather than a personal address. The recipient must confirm the
   subscription.

   ```bash
   aws sns subscribe --region REGION --protocol email --notification-endpoint EMAIL \
     --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts
   ```

2. Create the alarm, named `DSQL-Hourly-DPU-Budget-Warning-CLUSTER_ID` to match the policies above.
   `put-metric-alarm` overwrites an alarm of the same name, so each cluster needs its own. For
   another cluster in the same Region, the topic and key already allow it: run the step 1 lookups,
   then steps 2 and 3. In the console: cluster **Summary** tab, **Usage and cost** panel,
   **Create alarm** — it prefills `TotalDPU`, the namespace and `ClusterId`; set **Sum**, a 1-hour
   period, the threshold, **Missing data treatment** to not breaching, and the topic from step 1
   (not a new one) for both the alarm and OK states. Or with the AWS CLI:

   ```bash
   aws cloudwatch put-metric-alarm --region REGION \
     --alarm-name DSQL-Hourly-DPU-Budget-Warning-CLUSTER_ID \
     --namespace AWS/AuroraDSQL --metric-name TotalDPU \
     --dimensions Name=ClusterId,Value=CLUSTER_ID \
     --statistic Sum --period 3600 --evaluation-periods 1 --datapoints-to-alarm 1 \
     --threshold THRESHOLD --comparison-operator GreaterThanThreshold \
     --treat-missing-data notBreaching \
     --alarm-actions arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts \
     --ok-actions arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts
   ```

3. Verify the setup. `describe-alarms` must show the alarm on `CLUSTER_ID` with the topic in its
   actions, and `list-subscriptions-by-topic` must show the email confirmed. For a user's own alarm
   (from `describe-alarms-for-metric` with step 2's namespace, metric and dimensions), check
   `ActionsEnabled` and use its name and topic instead. If the email is still
   `PendingConfirmation`, ask the user to confirm it and check again; until it shows a subscription
   ARN, notifications reach no one:

   ```bash
   aws cloudwatch describe-alarms --region REGION \
     --alarm-names DSQL-Hourly-DPU-Budget-Warning-CLUSTER_ID
   aws sns list-subscriptions-by-topic --region REGION \
     --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:dsql-cost-alerts
   ```

   Then test delivery now rather than at the first real breach. For a user's own alarm, first list
   its `AlarmActions`, `OKActions` and `InsufficientDataActions`: the test runs the alarm actions,
   and its return to the real state runs that state's actions, not just this topic. Name any others
   (Lambda, Auto Scaling, other topics) when asking, and skip the test if the user does not agree.
   Ask the user before sending a test
   email to every subscriber (and possibly an OK email when the alarm returns to its real state,
   usually within a minute). Once they agree, force the alarm into `ALARM` with `set-alarm-state`,
   which needs `cloudwatch:SetAlarmState`; if it is already `ALARM`, set it to `OK` first (this also
   sends an OK email; include it when asking), then record `START`. `describe-alarm-history` since
   `START` must then show `Successfully executed action` with `NewStateValue` `ALARM` in its
   `publishedMessage` (a JSON string; match the text). If the entry is missing, rerun it with the
   same `START` every 10 seconds for up to 90 seconds, then report to the user. An SNS or KMS
   authorization error means the key or topic policy from step 1 does not allow this alarm. Then
   ask the user whether the test email arrived. Report the setup as verified only if the
   subscription is confirmed, the history entry is present and the email arrived; otherwise report
   it as not verified: notifications may not be delivered.

   ```bash
   # Only after the user agrees to the test email
   START=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "START=$START"
   aws cloudwatch set-alarm-state --region REGION \
     --alarm-name DSQL-Hourly-DPU-Budget-Warning-CLUSTER_ID \
     --state-value ALARM --state-reason "Delivery test"
   aws cloudwatch describe-alarm-history --region REGION \
     --alarm-name DSQL-Hourly-DPU-Budget-Warning-CLUSTER_ID --history-item-type Action \
     --start-date "$START"
   ```

   Then tell the user what the alarm covers — this cluster's hourly DPU usage, including any CDC
   streaming — and what it does not: storage, other Regions and month-to-date spend. It notifies
   but does not cap spending.

## Limits

- The alarm checks single hours, not month-to-date spend: a spiky hour can alarm while the month
  stays under budget. Use AWS Budgets for cumulative spend, including charges outside Aurora DSQL.
- Multi-Region clusters: repeat steps 1–3 in each Region — the key, topic and alarm are regional
  — on that Region's cluster ID, with that Region's share of the budget.
- CDC: `TotalDPU` already includes `StreamDPU`, summed across all streams. For one stream's share,
  read `StreamDPU` with dimensions `ClusterId` and `StreamId`.
