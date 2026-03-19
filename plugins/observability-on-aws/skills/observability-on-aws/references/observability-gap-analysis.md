# Codebase Observability Gap Analysis

## Purpose

Guidance for analyzing codebases to identify observability gaps and provide actionable recommendations for instrumentation, logging, metrics, and tracing.

## Analysis Framework

### 1. Logging Analysis

**What to Check:** Error handling blocks without logging, missing structured logging (JSON format), inconsistent log levels, missing correlation IDs/request IDs, sensitive data in logs (PII, credentials), missing context (user, session, transaction).

**Recommendations:** Use structured logging libraries (structlog, logrus, winston). Add correlation IDs to all entries. Log at appropriate levels. Include contextual metadata (service, version, environment). Sanitize sensitive data.

### 2. Metrics Collection

**What to Check:** Missing business metrics (orders, signups, conversions), no performance metrics (latency, throughput), missing resource utilization metrics, no error rate tracking, missing custom CloudWatch metrics, no metric dimensions.

**Recommendations:** Instrument key business operations. Track request duration and count. Monitor error rates by type. Add custom CloudWatch metrics for business KPIs. Use metric dimensions (service, endpoint, status).

### 3. Distributed Tracing

**What to Check:** Missing OpenTelemetry SDK integration, no trace context propagation (W3C Trace Context), missing spans for external calls, no span attributes for business context, no sampling strategy, legacy X-Ray SDK without OTEL migration path.

**Recommendations:** Use OpenTelemetry for instrumentation (vendor-neutral). Deploy ADOT as the collector. Enable AWS Application Signals for automatic APM. Propagate trace context across service boundaries. Implement adaptive sampling for high-volume services.

### 4. Error Handling

**What to Check:** Silent failures (empty catch blocks), generic error messages, missing error context, no error categorization, missing retry logic, no circuit breaker patterns.

**Recommendations:** Log all errors with full context. Use specific error types/classes. Include stack traces. Categorize errors (transient, permanent, user). Implement exponential backoff. Add circuit breakers for external dependencies.

### 5. Health Checks & Readiness

**What to Check:** Missing health check endpoints, no readiness probes, incomplete dependency checks, no graceful shutdown handling.

**Recommendations:** Implement `/health` and `/ready` endpoints. Include version and build info. Implement graceful shutdown. Add startup probes for slow-starting services.

## Analysis Workflow

1. **Scan Entry Points** - API endpoints/routes, Lambda handlers, message queue consumers, scheduled jobs
2. **Identify Critical Paths** - Authentication, payment processing, data mutations, external service calls
3. **Check Instrumentation** - Logging at entry/exit, error handling coverage, metrics emission, trace propagation
4. **Generate Report** - List gaps by severity, provide code examples, estimate effort, prioritize recommendations

## Common Observability Gaps

**Critical:** No error logging, missing trace context, silent failures (empty catch blocks), no health checks, sensitive data exposure in logs.

**High:** Unstructured logging (print/console.log), missing correlation IDs, no custom CloudWatch metrics, generic error messages, missing request/response logging.

**Medium:** Inconsistent log levels, missing business metrics, no sampling strategy, insufficient debugging context, logs not centralized.

**Low:** Verbose DEBUG output in production, missing log rotation, no log retention policy, inconsistent naming conventions, missing runbooks.

## Actionable Recommendations Template

For each gap identified, provide:

- **Gap:** Description
- **Severity:** Critical/High/Medium/Low
- **Location:** File:Line or Pattern
- **Impact:** What problems this causes
- **Recommendation:** Specific fix with before/after code
- **Effort:** Hours/Days estimate
- **Priority:** 1-5

## Integration with AWS Observability

1. **CloudWatch Logs** - Configure log groups per service, set retention policies, enable Log Insights, use metric filters
2. **CloudWatch Metrics** - Define custom metrics with limited dimensions, set up dashboards and alarms, use EMF for Lambda
3. **OpenTelemetry + ADOT + Application Signals** - Integrate OTEL SDK, deploy ADOT Collector, enable Application Signals for automatic APM, configure sampling rules, export to X-Ray/CloudWatch
4. **Application Signals (APM)** - Automatic service discovery, SLO tracking and error budgets, service health monitoring (P50/P90/P99), correlation across traces/metrics/logs

## Best Practices Checklist

- [ ] Structured logging with JSON format
- [ ] Correlation IDs in all logs
- [ ] Error logging with stack traces
- [ ] Metrics for key operations
- [ ] Distributed tracing with OpenTelemetry
- [ ] Health check endpoints
- [ ] Graceful error handling
- [ ] No sensitive data in logs
- [ ] Log levels used appropriately
- [ ] Business and performance metrics tracked
- [ ] Trace context propagated
- [ ] Sampling strategy defined

For language-specific code patterns and examples, see `observability-language-patterns.md`.
