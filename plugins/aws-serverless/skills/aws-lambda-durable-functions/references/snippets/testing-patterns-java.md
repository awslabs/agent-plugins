# Testing Patterns - Java

## Maven Test Dependency

```xml
<dependency>
  <groupId>software.amazon.lambda.durable</groupId>
  <artifactId>aws-durable-execution-sdk-java-testing</artifactId>
  <version>0.1.0</version>
  <scope>test</scope>
</dependency>
```

## Local Testing

```java
import software.amazon.lambda.durable.testing.LocalDurableTestRunner;
import software.amazon.lambda.durable.testing.OperationStatus;

@Test
void shouldExecuteWorkflow() {
    var runner = LocalDurableTestRunner.create(MyOutput.class, new MyHandler());
    var result = runner.runUntilComplete(Map.of("userId", "123"));
    assertEquals(OperationStatus.SUCCEEDED, result.getStatus());
    assertEquals("expected-value", result.getResult().getValue());
}
```

## Get Operations by Name

```java
var fetchOp = result.getOperation("fetch-user");
assertEquals(OperationStatus.SUCCEEDED, fetchOp.getStatus());
var processOp = result.getOperation("process-data");
assertEquals(OperationStatus.SUCCEEDED, processOp.getStatus());
```

## Run Until Waiting (Callbacks)

```java
var runner = LocalDurableTestRunner.create(MyOutput.class, new MyHandler());
var result = runner.runUntilWaiting(Map.of("approver", "[email]"));
var callbackOp = result.getOperation("wait-for-approval");
assertEquals(OperationStatus.WAITING, callbackOp.getStatus());
```

## Time Control

```java
var runner = LocalDurableTestRunner.create(MyOutput.class, new MyHandler())
    .withSkipTime(false);
var result = runner.runUntilWaiting(Map.of());
runner.advanceTime(Duration.ofSeconds(60));
var finalResult = runner.runUntilComplete(Map.of());
var waitOp = finalResult.getOperation("delay");
assertEquals(OperationStatus.SUCCEEDED, waitOp.getStatus());
```

## Error Scenarios

```java
@Test
void shouldRetryOnFailure() {
    var runner = LocalDurableTestRunner.create(MyOutput.class, new RetryHandler());
    var result = runner.runUntilComplete(Map.of());
    assertEquals(OperationStatus.SUCCEEDED, result.getStatus());
    assertEquals(OperationStatus.SUCCEEDED, result.getOperation("flaky-operation").getStatus());
}

@Test
void shouldFailAfterMaxRetries() {
    var runner = LocalDurableTestRunner.create(MyOutput.class, new AlwaysFailHandler());
    var result = runner.runUntilComplete(Map.of());
    assertEquals(OperationStatus.FAILED, result.getStatus());
}
```

## Concurrent Operations

```java
var result = runner.runUntilComplete(Map.of("items", List.of(1, 2, 3, 4, 5)));
var mapOp = result.getOperation("process-items");
assertEquals(OperationStatus.SUCCEEDED, mapOp.getStatus());
```

## Cloud Testing

```java
import software.amazon.lambda.durable.testing.CloudDurableTestRunner;

@Test
void shouldExecuteInRealLambda() {
    var runner = CloudDurableTestRunner.create("my-durable-function:1", "us-east-1");
    var result = runner.runUntilComplete(Map.of("userId", "123"));
    assertEquals(OperationStatus.SUCCEEDED, result.getStatus());
    assertEquals(OperationStatus.SUCCEEDED, result.getOperation("fetch-user").getStatus());
}
```
