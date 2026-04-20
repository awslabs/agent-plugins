# Thread Safety for LMI

LMI runs multiple invocations concurrently in the same execution environment. Code must be thread-safe.

## Code Review Checklist

When reviewing a function for LMI readiness, check each item:

- [ ] No global/static mutable variables (use immutable or request-local state)
- [ ] No shared `/tmp` paths (use request ID in filenames, clean up after)
- [ ] Thread-safe libraries only (check DB drivers, HTTP clients, caching libs)
- [ ] Database connections use pools (initialized outside handler, not per-invocation)
- [ ] SDK clients outside handler (module-level singletons are fine — they are thread-safe)
- [ ] No request state in global scope (use AsyncLocalStorage, contextvars, ThreadLocal)
- [ ] Logging includes request ID (for tracing concurrent requests)
- [ ] No environment variable mutation during requests (os.environ is shared)

## Runtime-Specific Guidance

### Node.js
- Async/await model naturally suits multi-concurrency
- Use `AsyncLocalStorage` from `node:async_hooks` for request context
- Initialize SDK clients and DB pools at module level
- Avoid module-level mutable state (`let count = 0` is a race condition)

### Python
- Uses separate processes per env (GIL limits true threading), but concurrent requests still share the process
- Use `contextvars` for request-specific data
- Use `threading.Lock` for shared mutable state
- Prefer 4:1 or 8:1 memory ratio (GIL limits CPU utilization)
- Use `ThreadedConnectionPool` for database connections

### Java
- Use immutable objects and thread-safe collections (`ConcurrentHashMap`, `Collections.unmodifiableList`)
- Initialize SDK clients and connection pools in constructor or static block
- Avoid mutable `static` fields
- Use `ThreadLocal<T>` for request-specific state
- Use HikariCP or similar for connection pooling

### .NET
- Use `AsyncLocal<T>` for request-scoped data
- Inject scoped services via DI container
- Initialize `HttpClient` and SDK clients as singletons
- Use `ConcurrentDictionary<T>` instead of `Dictionary<T>` for shared state

## Common Anti-Patterns

| Anti-pattern | Risk | Fix |
|-------------|------|-----|
| Singleton HTTP clients per invocation | Wasted connections | Module-level initialization |
| Setting env vars during request | Race condition | Pass state via parameters |
| Logging without request ID | Unreadable interleaved logs | Include aws_request_id |
| Assuming sequential execution | State corruption | Each invocation must be self-contained |
