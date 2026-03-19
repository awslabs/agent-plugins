# Observability Language Patterns

Language-specific observability patterns with GOOD/BAD code examples.

## Python (structlog)

```python
# GOOD: Structured logging with context
import structlog
logger = structlog.get_logger()
def process_order(order_id, user_id):
    log = logger.bind(order_id=order_id, user_id=user_id)
    try:
        log.info("processing_order_started")
        log.info("processing_order_completed", duration_ms=duration)
    except Exception as e:
        log.error("processing_order_failed", error=str(e), exc_info=True)
        raise
# BAD: Unstructured, no context, silent failure
def process_order(order_id, user_id):
    try: print("Processing order")
    except: pass
```

## Java (SLF4J + MDC)

```java
// GOOD: Structured logging with MDC
public void processOrder(String orderId, String userId) {
    MDC.put("orderId", orderId); MDC.put("userId", userId);
    try {
        logger.info("Processing order started");
    } catch (Exception e) {
        logger.error("Processing order failed", e); throw e;
    } finally { MDC.clear(); }
}
// BAD: No context, silent failure
public void processOrder(String orderId, String userId) {
    try { System.out.println("Processing"); }
    catch (Exception e) { /* silent */ }
}
```

## JavaScript/TypeScript (Winston)

```javascript
// GOOD: Structured logging with Winston
const logger = winston.createLogger({
  format: winston.format.json(),
  defaultMeta: { service: 'order-service' },
});
async function processOrder(orderId, userId) {
  const log = logger.child({ orderId, userId });
  try {
    log.info('Processing order started');
  } catch (error) {
    log.error('Processing order failed', { error: error.message, stack: error.stack });
    throw error;
  }
}
// BAD: Console logging, silent failure
async function processOrder(orderId, userId) {
  try { console.log('Processing order'); }
  catch (error) { /* silent */ }
}
```

## Go (zerolog)

```go
// GOOD: Structured logging with zerolog
func processOrder(orderID, userID string) error {
    logger := log.With().Str("order_id", orderID).Str("user_id", userID).Logger()
    logger.Info().Msg("Processing order started")
    if err := doWork(); err != nil {
        logger.Error().Err(err).Msg("Processing order failed")
        return err
    }
    return nil
}
// BAD: No structure, no error logging
func processOrder(orderID, userID string) error {
    fmt.Println("Processing order")
    if err := doWork(); err != nil { return err }
    return nil
}
```

## Cost Optimization

**Logging:** Production level INFO/WARN. Sample high-throughput (1 in 100). CloudWatch retention 7-30 days. EMF for Lambda. Avoid hot-path logging.
**Metrics:** Max 10 dimensions per metric. Aggregate at source. Standard 1-min resolution. Use metric math in dashboards.
**Tracing:** Head-based sampling. Adaptive rates (higher for errors). 1% high-volume, 100% low-volume. Skip health checks. ADOT for local aggregation.

## Example Analysis Output

```markdown
# Observability Analysis: 45 files | Critical: 3 | High: 8 | Medium: 12

## Critical: Missing Error Logging in Payment Handler

Location: src/handlers/payment.py:45-60 | Fix: Add structured error logging
```
