# LMI Migration Patterns

Before/after code examples for migrating to multi-concurrency.

## Node.js

### Global State
```javascript
// BEFORE (race condition)
let requestCount = 0;
exports.handler = async (event) => {
  requestCount++;
  return { count: requestCount };
};

// AFTER (request-isolated)
const { AsyncLocalStorage } = require('node:async_hooks');
const als = new AsyncLocalStorage();
exports.handler = async (event) => {
  return als.run({ id: event.requestContext?.requestId }, async () => {
    return await processEvent(event);
  });
};
```

### File I/O
```javascript
// BEFORE (shared path)
fs.writeFileSync('/tmp/output.json', JSON.stringify(data));

// AFTER (request-unique path)
const path = `/tmp/output-${event.requestContext?.requestId}.json`;
try { fs.writeFileSync(path, JSON.stringify(data)); }
finally { fs.unlinkSync(path); }
```

### Database
```javascript
// BEFORE (per-invocation connection)
exports.handler = async (event) => {
  const conn = await mysql.createConnection({/*...*/});
  const [rows] = await conn.execute('SELECT ...');
  await conn.end();
};

// AFTER (shared pool)
const pool = mysql.createPool({ connectionLimit: 10, /*...*/ });
exports.handler = async (event) => {
  const [rows] = await pool.execute('SELECT ...');
  return rows;
};
```

## Python

### Global State
```python
# BEFORE (race condition)
cache = {}
def handler(event, context):
    cache[event['key']] = compute(event)

# AFTER (thread-safe)
import threading
_lock = threading.Lock()
_cache = {}
def handler(event, context):
    with _lock:
        if event['key'] not in _cache:
            _cache[event['key']] = compute(event)
        return _cache[event['key']]
```

### File I/O
```python
# BEFORE
with open('/tmp/data.json', 'w') as f: json.dump(event, f)

# AFTER
path = f'/tmp/data-{context.aws_request_id}.json'
try:
    with open(path, 'w') as f: json.dump(event, f)
finally:
    os.unlink(path)
```

### Database
```python
# BEFORE (per-invocation)
def handler(event, context):
    conn = psycopg2.connect(host='...')

# AFTER (pool)
from psycopg2 import pool
db_pool = pool.ThreadedConnectionPool(2, 10, host=os.environ['DB_HOST'])
def handler(event, context):
    conn = db_pool.getconn()
    try: return query(conn, event)
    finally: db_pool.putconn(conn)
```

## Java

### Global State
```java
// BEFORE (race condition)
private static Map<String, String> cache = new HashMap<>();

// AFTER (thread-safe)
private static final ConcurrentHashMap<String, String> cache = new ConcurrentHashMap<>();
// Use cache.computeIfAbsent(key, k -> compute(k));
```

### Database
```java
// BEFORE (per-invocation)
Connection conn = DriverManager.getConnection("jdbc:...");

// AFTER (HikariCP pool, static init)
private static final HikariDataSource ds;
static {
    HikariConfig c = new HikariConfig();
    c.setJdbcUrl(System.getenv("DB_URL"));
    c.setMaximumPoolSize(10);
    ds = new HikariDataSource(c);
}
// Use: try (Connection conn = ds.getConnection()) { ... }
```
