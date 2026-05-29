# Hibernate / Spring Boot Migration Guide for DSQL

How to run Java applications with Hibernate and Spring Boot against Aurora DSQL.

Sources:

- [Aurora DSQL Hibernate Adapter](https://github.com/awslabs/aurora-dsql-orms/tree/main/java/hibernate)
- [JDBC + HikariCP Sample](https://github.com/aws-samples/aurora-dsql-samples/tree/main/java/pgjdbc)
- [Spring Boot Sample](https://github.com/aws-samples/aurora-dsql-samples/tree/main/java/spring_boot)
- [Liquibase Sample](https://github.com/aws-samples/aurora-dsql-samples/tree/main/java/liquibase)

---

## 1. Dependencies

```xml
<dependency>
    <groupId>software.amazon.dsql</groupId>
    <artifactId>aurora-dsql-hibernate</artifactId>
    <version>LATEST</version>
</dependency>
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>dsql</artifactId>
</dependency>
```

## 2. Configuration

```yaml
# application.yml
spring:
  datasource:
    url: jdbc:postgresql://<cluster-id>.<region>.dsql.amazonaws.com:5432/postgres?sslmode=require
    hikari:
      maximum-pool-size: 10
      max-lifetime: 1800000    # 30 min (below DSQL 1-hour timeout)
  jpa:
    database-platform: software.amazon.dsql.hibernate.AuroraDsqlDialect
    hibernate:
      ddl-auto: none           # NEVER use auto DDL with DSQL
    properties:
      hibernate.jdbc.batch_size: 100
```

**Critical:** `ddl-auto` MUST be `none`. Hibernate's auto-DDL batches multiple statements.

## 3. Entity Changes

### Remove @ManyToOne / @OneToMany

```java
// BAD: Hibernate creates FK constraint
@Entity
public class Ticket {
    @ManyToOne
    @JoinColumn(name = "org_id")
    private Organization org;
}

// GOOD: Plain column + service-layer validation
@Entity
@Table(name = "tickets")
public class Ticket {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "org_id", nullable = false)
    private Long orgId;

    @Column(name = "reporter_id", nullable = false)
    private UUID reporterId;

    @Column(name = "metadata", columnDefinition = "json")
    private String metadata;
}
```

### Sequence Configuration

```java
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
@SequenceGenerator(name = "order_seq", sequenceName = "order_seq", allocationSize = 1)
private Long id;
// allocationSize MUST match DSQL CACHE value (1 or 65536)
```

## 4. OCC Retry with Spring Retry

```java
@Retryable(
    retryFor = {LockAcquisitionException.class},
    maxAttempts = 5,
    backoff = @Backoff(delay = 50, multiplier = 2, maxDelay = 5000)
)
@Transactional
public Order createOrder(UUID customerId, BigDecimal total) {
    if (!customerRepository.existsById(customerId)) {
        throw new EntityNotFoundException("Customer not found");
    }
    return orderRepository.save(new Order(customerId, total));
}
```

## 5. Liquibase (One DDL Per Changeset)

```xml
<changeSet id="1" author="dev">
    <createTable tableName="orders">
        <column name="id" type="uuid" defaultValueComputed="gen_random_uuid()">
            <constraints primaryKey="true"/>
        </column>
        <column name="total" type="numeric(10,2)"/>
    </createTable>
</changeSet>
<changeSet id="2" author="dev">
    <sql>CREATE INDEX ASYNC idx_orders_customer ON orders (customer_id)</sql>
</changeSet>
```

## 6. Batch Operations (Under 3,000 Rows)

```java
@Transactional
public void bulkInsert(List<Order> orders) {
    List<List<Order>> batches = Lists.partition(orders, 500);
    for (List<Order> batch : batches) {
        orderRepository.saveAll(batch);
        entityManager.flush();
        entityManager.clear();
    }
}
```

## 7. Checklist

- [ ] Add `aurora-dsql-hibernate` dialect dependency
- [ ] Set `hibernate.ddl-auto = none`
- [ ] Replace `@ManyToOne` / `@OneToMany` with plain columns
- [ ] Add service-layer FK validation
- [ ] Set sequence `allocationSize` to match DSQL CACHE
- [ ] Add Spring Retry for OCC (SQLSTATE 40001)
- [ ] Set HikariCP `maxLifetime` ≤ 1800000ms
- [ ] Batch writes to ≤500 rows per transaction
- [ ] Use Liquibase with one DDL per changeset
