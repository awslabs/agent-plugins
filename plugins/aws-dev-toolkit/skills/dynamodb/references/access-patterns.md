# DynamoDB Access Pattern Examples

Key design examples, GSI/LSI strategies, and single-table design patterns.

## Single-Table Design: E-Commerce

### Access Patterns

| # | Access Pattern | Key Condition | Index |
|---|---|---|---|
| 1 | Get user profile | PK=USER#\<id\> SK=PROFILE | Base table |
| 2 | List user's orders | PK=USER#\<id\> SK begins_with ORDER# | Base table |
| 3 | Get order by ID | PK=ORDER#\<id\> SK=METADATA | Base table |
| 4 | Get order items | PK=ORDER#\<id\> SK begins_with ITEM# | Base table |
| 5 | Orders by status | GSI1PK=STATUS#\<status\> GSI1SK=\<timestamp\> | GSI1 |
| 6 | Look up user by email | GSI2PK=EMAIL#\<email\> GSI2SK=USER#\<id\> | GSI2 |
| 7 | Recent orders (global) | GSI1PK=ORDER GSI1SK=\<timestamp\> | GSI1 (overloaded) |

### Table Schema

| Entity | PK | SK | GSI1PK | GSI1SK | GSI2PK | GSI2SK | Attributes |
|---|---|---|---|---|---|---|---|
| User | USER#\<id\> | PROFILE | - | - | EMAIL#\<email\> | USER#\<id\> | name, email, plan |
| Order | USER#\<id\> | ORDER#\<timestamp\>#\<orderId\> | STATUS#\<status\> | \<timestamp\> | - | - | total, status |
| Order (by ID) | ORDER#\<id\> | METADATA | ORDER | \<timestamp\> | - | - | userId, total, status |
| Order Item | ORDER#\<id\> | ITEM#\<sku\> | - | - | - | - | quantity, price, name |

### Key Design Decisions

- **User orders by recency:** Sort key `ORDER#<timestamp>#<orderId>` gives chronological order. Query with `ScanIndexForward=false` for newest first.
- **Order has two entries:** One under `USER#<id>` for "my orders" and one under `ORDER#<id>` for direct lookup. This denormalization is intentional.
- **Status filter via GSI1:** Partition by status, sort by timestamp. Enables "show all PENDING orders, newest first."
- **Email lookup via GSI2:** Unique email constraint enforced by `PutItem` with `attribute_not_exists(GSI2PK)` condition.

## Single-Table Design: Multi-Tenant SaaS

### Access Patterns

| # | Access Pattern | Key Condition | Index |
|---|---|---|---|
| 1 | Get tenant settings | PK=TENANT#\<id\> SK=SETTINGS | Base table |
| 2 | List tenant users | PK=TENANT#\<id\> SK begins_with USER# | Base table |
| 3 | Get user by ID | PK=TENANT#\<id\> SK=USER#\<userId\> | Base table |
| 4 | User's projects | PK=TENANT#\<id\>#USER#\<userId\> SK begins_with PROJECT# | Base table |
| 5 | Look up user by email (cross-tenant) | GSI1PK=EMAIL#\<email\> | GSI1 |
| 6 | List projects by status | GSI2PK=TENANT#\<id\>#STATUS#\<status\> GSI2SK=\<timestamp\> | GSI2 |
| 7 | All items for a tenant (export) | PK begins_with TENANT#\<id\> | Scan with filter (offline only) |

### Table Schema

| Entity | PK | SK | GSI1PK | GSI1SK | GSI2PK | GSI2SK |
|---|---|---|---|---|---|---|
| Tenant | TENANT#\<id\> | SETTINGS | - | - | - | - |
| User | TENANT#\<id\> | USER#\<userId\> | EMAIL#\<email\> | TENANT#\<id\> | - | - |
| Project | TENANT#\<id\>#USER#\<userId\> | PROJECT#\<timestamp\> | - | - | TENANT#\<id\>#STATUS#\<status\> | \<timestamp\> |

### Key Design Decisions

- **Tenant isolation at partition level:** All tenant data shares the TENANT# prefix. No cross-tenant queries possible from the base table.
- **Composite PK for user-scoped data:** `TENANT#<id>#USER#<userId>` scopes projects to a specific user within a tenant.
- **Cross-tenant email uniqueness:** GSI1 with `EMAIL#<email>` as PK enables global email lookup while maintaining tenant isolation on the base table.

## GSI Overloading

Use generic GSI key names and load different entity types into the same GSI for multiple access patterns.

```
GSI1PK                      GSI1SK                  Entity
─────────────────────────────────────────────────────────────
EMAIL#alice@example.com     USER#123                User (email lookup)
STATUS#PENDING              2024-01-15T10:00:00Z    Order (by status)
CATEGORY#electronics        PRICE#0000099.99        Product (by category+price)
```

**Rules for GSI overloading:**
- Use generic names: `GSI1PK`, `GSI1SK`
- Only project attributes needed for that access pattern (saves storage and WCU)
- Document which entity types use which GSI and what the key values mean

## Hierarchical Sort Keys

Model hierarchies in the sort key for flexible prefix queries.

```
PK: LOCATION
SK: USA#CA#SAN_FRANCISCO#94102

Query options:
- All in USA:           SK begins_with "USA#"
- All in California:    SK begins_with "USA#CA#"
- All in San Francisco: SK begins_with "USA#CA#SAN_FRANCISCO#"
- Specific zip:         SK = "USA#CA#SAN_FRANCISCO#94102"
```

Works well for: geographic hierarchies, org charts, category trees, file paths.

## Composite Sort Key for Time-Series + Filtering

Combine status and timestamp in the sort key for filtered time-range queries.

```
PK: DEVICE#sensor-42
SK: ACTIVE#2024-01-15T10:30:00Z

Query: All active readings for sensor-42 in January 2024
  PK = "DEVICE#sensor-42"
  SK between "ACTIVE#2024-01-01" and "ACTIVE#2024-02-01"
```

**Limitation:** You can only do range queries on one "dimension" at a time. If you need range queries on both status and time independently, use a GSI.

## Adjacency List Pattern

Model graph-like relationships (many-to-many) in a single table.

```
PK              SK              Data
────────────────────────────────────────────
USER#alice      USER#alice      {name: "Alice", ...}
USER#alice      GROUP#admins    {joinedAt: "2024-01-01", role: "owner"}
USER#alice      GROUP#devs      {joinedAt: "2024-03-01", role: "member"}
GROUP#admins    GROUP#admins    {name: "Admins", ...}
GROUP#admins    USER#alice      {joinedAt: "2024-01-01", role: "owner"}
GROUP#admins    USER#bob        {joinedAt: "2024-02-01", role: "member"}
```

**Access patterns served:**
- Get user profile: PK=USER#alice, SK=USER#alice
- List user's groups: PK=USER#alice, SK begins_with GROUP#
- List group members: PK=GROUP#admins, SK begins_with USER#
- Get group info: PK=GROUP#admins, SK=GROUP#admins

**Trade-off:** Duplicated relationship records (one from each side). Writes are more expensive, but reads are single-query.

## Sparse Index Pattern

A GSI where most items do not have the GSI key attributes. Only items with those attributes appear in the index.

```
Base table items:
  {PK: "USER#1", SK: "PROFILE", name: "Alice"}                    ← NOT in GSI
  {PK: "USER#2", SK: "PROFILE", name: "Bob", flagged: "true", flaggedAt: "2024-01-15"}  ← IN GSI
  {PK: "USER#3", SK: "PROFILE", name: "Carol"}                    ← NOT in GSI

GSI: FlaggedUsersIndex
  GSI PK: flagged
  GSI SK: flaggedAt
```

Only flagged users appear in the index. Query the GSI to get all flagged users sorted by date, without scanning the entire table.

**Use cases:** Active sessions, items pending review, error records, promotional items.

## Write Sharding for Hot Partitions

When a partition key has very high write throughput, shard it across multiple partitions.

```
Instead of:  PK = "COUNTER"          (hot partition)
Use:         PK = "COUNTER#" + random(0, 9)   (10 shards)

To read the total: Query all 10 shards and sum the values.
```

**When to use:** Global counters, leaderboards, or any item that receives hundreds of writes per second.

**Implementation:**
```python
# Write: pick a random shard
shard = random.randint(0, NUM_SHARDS - 1)
table.update_item(
    Key={"PK": f"COUNTER#{shard}", "SK": "TOTAL"},
    UpdateExpression="ADD #val :inc",
    ExpressionAttributeNames={"#val": "value"},
    ExpressionAttributeValues={":inc": 1}
)

# Read: sum all shards
total = 0
for shard in range(NUM_SHARDS):
    response = table.get_item(Key={"PK": f"COUNTER#{shard}", "SK": "TOTAL"})
    total += response.get("Item", {}).get("value", 0)
```

## Pattern Selection Quick Reference

| Problem | Pattern | Notes |
|---|---|---|
| Multiple entity types, shared partition key | Single-table design | Use generic PK/SK names |
| Multiple access patterns, different partition keys | GSI per access pattern | Max 20 GSIs per table |
| Same GSI serves multiple entity types | GSI overloading | Document the key semantics |
| Hierarchical data | Hierarchical sort keys | `begins_with` for prefix queries |
| Many-to-many relationships | Adjacency list | Duplicate entries for both directions |
| Query only a subset of items | Sparse index | Only items with GSI attrs appear |
| Hot write partition | Write sharding | Random suffix on PK, aggregate on read |
| Large items (>400 KB) | Store in S3, pointer in DynamoDB | Claim-check pattern |
