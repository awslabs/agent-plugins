# Getting Started - Java

## Maven Setup

```xml
<dependency>
  <groupId>software.amazon.lambda.durable</groupId>
  <artifactId>aws-durable-execution-sdk-java</artifactId>
  <version>0.1.0</version>
</dependency>
<dependency>
  <groupId>software.amazon.lambda.durable</groupId>
  <artifactId>aws-durable-execution-sdk-java-testing</artifactId>
  <version>0.1.0</version>
  <scope>test</scope>
</dependency>
```

## Basic Handler

```java
public class MyHandler extends DurableHandler<MyInput, MyOutput> {
  @Override
  public MyOutput handleRequest(MyInput event, DurableContext ctx) {
    var userData = ctx.step("fetch-user", UserData.class, s -> fetchUserFromDB(event.getUserId()));
    ctx.wait(null, Duration.ofSeconds(5));
    var result = ctx.step("process", ProcessResult.class, s -> processUser(userData));
    return new MyOutput(true, result);
  }
}
```

## Multi-Step Workflow

```java
public class WorkflowHandler extends DurableHandler<WorkflowInput, WorkflowOutput> {
  @Override
  public WorkflowOutput handleRequest(WorkflowInput event, DurableContext ctx) {
    var validated = ctx.step("validate", ValidatedData.class, s -> validateInput(event));
    var processed = ctx.step("process", ProcessedData.class, s -> processData(validated));
    ctx.wait("cooldown", Duration.ofSeconds(30));
    ctx.step("notify", Void.class, s -> { sendNotification(processed); return null; });
    return new WorkflowOutput(true);
  }
}
```

## GenAI Agent (Agentic Loop)

```java
public class AgentHandler extends DurableHandler<AgentInput, String> {
  @Override
  public String handleRequest(AgentInput event, DurableContext ctx) {
    var messages = new ArrayList<>(List.of(Map.of("role", "user", "content", event.getPrompt())));
    while (true) {
      var result = ctx.step("invoke-model", ModelResult.class, s -> invokeAIModel(messages));
      if (result.getTool() == null) return result.getResponse();
      var toolResult = ctx.step("tool-" + result.getTool().getName(), String.class,
        s -> executeTool(result.getTool(), result.getResponse()));
      messages.add(Map.of("role", "assistant", "content", toolResult));
    }
  }
}
```

## Human-in-the-Loop Approval

```java
public class ApprovalHandler extends DurableHandler<ApprovalInput, ApprovalOutput> {
  @Override
  public ApprovalOutput handleRequest(ApprovalInput event, DurableContext ctx) {
    var plan = ctx.step("generate-plan", Plan.class, s -> generatePlan(event));
    var answer = ctx.waitForCallback("wait-for-approval", String.class,
      (callbackId, s) -> sendApprovalEmail(event.getApproverEmail(), plan, callbackId));
    if ("APPROVED".equals(answer)) {
      ctx.step("execute", Void.class, s -> { performAction(plan); return null; });
      return new ApprovalOutput("completed");
    }
    return new ApprovalOutput("rejected");
  }
}
```

## Saga Pattern

```java
public class SagaHandler extends DurableHandler<BookingInput, BookingOutput> {
  @Override
  public BookingOutput handleRequest(BookingInput event, DurableContext ctx) {
    var comps = new ArrayList<Runnable>();
    try {
      ctx.step("book-flight", Void.class, s -> { flightClient.book(event); return null; });
      comps.add(() -> ctx.step("cancel-flight", Void.class, s -> { flightClient.cancel(event); return null; }));
      ctx.step("book-hotel", Void.class, s -> { hotelClient.book(event); return null; });
      comps.add(() -> ctx.step("cancel-hotel", Void.class, s -> { hotelClient.cancel(event); return null; }));
      return new BookingOutput(true);
    } catch (Exception e) {
      Collections.reverse(comps);
      comps.forEach(Runnable::run);
      throw e;
    }
  }
}
```
