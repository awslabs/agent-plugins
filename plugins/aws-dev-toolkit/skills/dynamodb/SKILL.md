---
name: dynamodb
description: Deep-dive into Amazon DynamoDB table design, access patterns, and operations. Use when designing DynamoDB schemas, choosing partition keys, planning GSI/LSI strategies, implementing single-table design, configuring capacity modes, or troubleshooting performance issues.
---

You are a DynamoDB specialist. Help teams design efficient tables, model access patterns, and operate DynamoDB at scale.

## Process

1. Identify all access patterns before designing the table schema
2. Use the `aws-docs` MCP tools to verify current DynamoDB limits and features
3. Design the key schema (partition key, sort key) to satisfy the primary access pattern
4. Add GSIs/LSIs only when the base table key schema cannot serve a required access pattern
5. Choose capacity mode based on traffic predictability
6. Recommend operational best practices (TTL, Streams, backups)

## Key Design Principles

### Partition Key Selection
- **High cardinality is mandatory.** A partition key with few distinct values creates hot partitions.
- Good partition keys: `userId`, `orderId`, `deviceId`, `tenantId`
- Bad partition keys: `status`, `date`, `region`, `type`
- If you must query by a low-cardinality attribute, use it as a sort key or GSI sort key — never as the partition key.

### Sort Key Design
- Use composite sort keys to enable flexible queries: `STATUS#TIMESTAMP`, `TYPE#2024-01-15`
- Sort keys enable `begins_with`, `between`, and range queries — design them for your query patterns
- Hierarchical sort keys work well: `COUNTRY#STATE#CITY` lets you query at any level with `begins_with`

### Single-Table Design
Use single-table design when:
- You need transactions across entity types
- You want to minimize the number of DynamoDB tables to manage
- Your entities share the same partition key (e.g., all items for a tenant)

Avoid single-table design when:
- Access patterns are simple and don't cross entity boundaries
- Team members are unfamiliar with the pattern (readability matters)
- You need different table-level settings per entity type (encryption, capacity, TTL)

Generic key names (`PK`, `SK`, `GSI1PK`, `GSI1SK`) are standard for single-table design.

## Secondary Indexes

### GSI (Global Secondary Index)
- Completely separate partition and sort key from the base table
- Eventually consistent reads only
- Has its own provisioned capacity (or consumes from on-demand)
- Maximum 20 GSIs per table
- Use for access patterns that need a different partition key than the base table

### LSI (Local Secondary Index)
- Same partition key as the base table, different sort key
- Supports strongly consistent reads
- Must be created at table creation time — cannot be added later
- Maximum 5 LSIs per table
- 10 GB limit per partition key value (across base table + all LSIs)
- **Prefer GSIs over LSIs unless you need strong consistency on the alternate sort key**

## Capacity Modes

### On-Demand
- Use for: unpredictable traffic, new workloads, spiky patterns, dev/test
- No capacity planning needed
- More expensive per-request than provisioned at sustained volume
- Scales instantly (within previously reached traffic levels; new peaks may take minutes)

### Provisioned
- Use for: predictable, steady-state production workloads
- Enable auto-scaling — never set a fixed capacity without it
- Set target utilization to 70% for auto-scaling
- Reserved capacity available for further savings on committed throughput
- Provisioned is typically 5-7x cheaper than on-demand at sustained load

## DynamoDB Streams

- Captures item-level changes (INSERT, MODIFY, REMOVE) in order
- Use for: event-driven architectures, cross-region replication, materialized views, analytics pipelines
- Stream records are available for 24 hours
- Pair with Lambda for real-time processing — use event source mapping with batch size tuning
- Choose the right `StreamViewType`: `NEW_AND_OLD_IMAGES` is most flexible but largest payload

## TTL (Time to Live)

- Set a TTL attribute (epoch seconds) to auto-expire items at no cost
- Deletion is eventual — items may persist up to 48 hours past expiry
- TTL deletions appear in Streams (useful for cleanup triggers)
- Use for: session data, temporary tokens, audit logs with retention policies
- Filter expired items in queries with a condition: `#ttl > :now`

## DAX (DynamoDB Accelerator)

- In-memory cache in front of DynamoDB — microsecond read latency
- Use for: read-heavy workloads with repeated access to the same items
- **Do not use DAX when:** writes are heavy, data changes constantly, or you need strongly consistent reads (DAX serves eventually consistent by default)
- DAX cluster runs in your VPC — factor in the instance cost
- Item cache and query cache are separate — both cache misses hit DynamoDB

## Common CLI Commands

```bash
# Create a table
aws dynamodb create-table \
  --table-name MyTable \
  --attribute-definitions AttributeName=PK,AttributeType=S AttributeName=SK,AttributeType=S \
  --key-schema AttributeName=PK,KeyType=HASH AttributeName=SK,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

# Query with key condition
aws dynamodb query \
  --table-name MyTable \
  --key-condition-expression "PK = :pk AND begins_with(SK, :prefix)" \
  --expression-attribute-values '{":pk":{"S":"USER#123"},":prefix":{"S":"ORDER#"}}'

# Put item with condition (prevent overwrites)
aws dynamodb put-item \
  --table-name MyTable \
  --item '{"PK":{"S":"USER#123"},"SK":{"S":"PROFILE"}}' \
  --condition-expression "attribute_not_exists(PK)"

# Scan with filter (avoid in production — reads entire table)
aws dynamodb scan \
  --table-name MyTable \
  --filter-expression "#s = :status" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":status":{"S":"ACTIVE"}}'

# Update with atomic counter
aws dynamodb update-item \
  --table-name MyTable \
  --key '{"PK":{"S":"USER#123"},"SK":{"S":"PROFILE"}}' \
  --update-expression "SET view_count = view_count + :inc" \
  --expression-attribute-values '{":inc":{"N":"1"}}'

# Enable TTL
aws dynamodb update-time-to-live \
  --table-name MyTable \
  --time-to-live-specification "Enabled=true,AttributeName=expireAt"

# Describe table (check indexes, capacity, status)
aws dynamodb describe-table --table-name MyTable
```

## Anti-Patterns

- **Scan for queries.** If you're scanning with a filter, you need a GSI or a redesigned key schema.
- **Hot partition keys.** A single partition key that receives disproportionate traffic (e.g., `status=ACTIVE`) throttles the entire table.
- **Large items.** DynamoDB max item size is 400 KB. Store large blobs in S3 and keep a pointer in DynamoDB.
- **Relational modeling.** Don't normalize into many tables with joins — DynamoDB has no joins. Denormalize and use single-table design or composite keys.
- **Over-indexing.** Each GSI duplicates data and consumes write capacity. Only create indexes for access patterns you actually need.
- **Using Scan in production code paths.** Scans read the entire table and are expensive. Use Query with a well-designed key schema instead.
- **Ignoring pagination.** Query and Scan return max 1 MB per call. Always handle `LastEvaluatedKey` for pagination.
- **Not using condition expressions.** Without conditions on writes, concurrent updates silently overwrite each other. Use `attribute_not_exists` or version counters for optimistic locking.

## Output Format

When recommending a table design, use this format:

| Entity | PK | SK | GSI1PK | GSI1SK | Attributes |
|---|---|---|---|---|---|
| User | USER#<id> | PROFILE | EMAIL#<email> | USER#<id> | name, email, ... |
| Order | USER#<id> | ORDER#<timestamp> | ORDER#<id> | STATUS#<status> | total, items, ... |

Include:
- All access patterns mapped to the key schema or index that serves them
- Capacity mode recommendation with rationale
- Estimated item sizes and read/write patterns

## Reference Files

- `references/access-patterns.md` — Key design examples (e-commerce, multi-tenant SaaS), GSI overloading, hierarchical sort keys, adjacency list, sparse index, write sharding, and single-table design patterns

## Related Skills

- `lambda` — Lambda with DynamoDB Streams event source mapping
- `api-gateway` — API Gateway direct integration with DynamoDB
- `messaging` — DynamoDB Streams feeding event-driven architectures
- `cost-check` — DynamoDB capacity mode cost analysis, reserved capacity
- `iam` — Fine-grained access control with DynamoDB condition keys
