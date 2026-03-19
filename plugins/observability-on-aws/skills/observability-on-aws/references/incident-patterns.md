# Common Incident Patterns

## Purpose

Common incident patterns with investigation approaches and prevention strategies. For the overall incident response framework, see `incident-response.md`. For detailed log query syntax, see `log-analysis.md`.

## Pattern 1: Deployment-Related Incident

**Symptoms**:

- Errors spike immediately after deployment
- Specific service shows elevated error rate
- Traces show new error types

**Investigation**: Query logs for errors after deployment timestamp. Group errors by type to identify new patterns. Compare error types before and after deployment. See `log-analysis.md` for query syntax.

**Mitigation**: Rollback deployment

**Prevention**: Implement canary deployments, add integration tests, improve staging environment

## Pattern 2: Resource Exhaustion

**Symptoms**:

- Gradual performance degradation
- Timeouts and connection errors
- High CPU or memory utilization

**Investigation**: Check CloudWatch Metrics for resource utilization. Query logs for timeout errors. Review Application Signals for latency increases. Check Billing & Cost Management for usage spikes.

**Mitigation**: Scale resources, optimize code

**Prevention**: Set up auto-scaling, implement resource limits, add capacity planning alarms

## Pattern 3: Dependency Failure

**Symptoms**:

- Errors calling external service
- Traces show failures in downstream calls
- Service map shows unhealthy dependency

**Investigation**: Filter logs for dependency-related errors. Parse service names and status codes. Correlate with Application Signals service map. Check traces for downstream call failures. See `log-analysis.md` for query syntax.

**Mitigation**: Implement circuit breaker, add fallback behavior, route around failed dependency

**Prevention**: Add dependency health checks, implement retry logic with backoff, set up dependency SLOs

## Pattern 4: Database Performance

**Symptoms**:

- Slow query performance
- Database connection pool exhaustion
- High database CPU utilization

**Investigation**: Parse SQL queries and durations from logs. Filter for slow queries (e.g., duration > 1000ms). Aggregate by query pattern to find the most impactful queries. Correlate with database CloudWatch Metrics (CPU, connections, IOPS). See `log-analysis.md` for query syntax.

**Mitigation**: Add database indexes, optimize queries, scale database resources, implement query caching

**Prevention**: Regular query performance reviews, database monitoring and alerting, connection pool tuning

## Pattern 5: Traffic Spike

**Symptoms**:

- Sudden increase in request volume
- Rate limiting errors
- Resource exhaustion

**Investigation**: Check CloudWatch Metrics for request rates. Query logs for request patterns. Review Application Signals for traffic sources. Check Billing & Cost Management for usage spikes.

**Mitigation**: Enable auto-scaling, implement rate limiting, add caching layer

**Prevention**: Capacity planning, load testing, auto-scaling configuration, DDoS protection
