# Strands Agent — TypeScript Patterns

## Minimal Agent (No Tools)

```typescript
// src/agent.ts
import { Agent } from '@strands-agents/sdk'

const agent = new Agent({
  systemPrompt: 'You are a helpful assistant.',
})

const result = await agent.invoke('What can you help me with?')
console.log(result.lastMessage)
```

## Agent with Custom Tools

```typescript
// src/agent.ts
import { Agent, tool } from '@strands-agents/sdk'
import z from 'zod'

const lookupOrder = tool({
  name: 'lookup_order',
  description: 'Look up an order by ID. Returns order status, items, and shipping info.',
  inputSchema: z.object({
    orderId: z.string().describe('The order ID to look up'),
  }),
  callback: async (input) => {
    // Replace with your actual data source
    return JSON.stringify({
      orderId: input.orderId,
      status: 'shipped',
      items: ['Widget A', 'Widget B'],
      trackingNumber: 'TRK-12345',
    })
  },
})

const agent = new Agent({
  systemPrompt: 'You are a customer service agent. Help users check their orders.',
  tools: [lookupOrder],
})

const result = await agent.invoke('Where is my order #ORD-789?')
console.log(result.lastMessage)
```

## Agent with Vended Tools (Built-in)

```typescript
import { Agent } from '@strands-agents/sdk'
import { bash } from '@strands-agents/sdk/vended-tools/bash'

const agent = new Agent({
  tools: [bash],
  systemPrompt: 'You are a DevOps assistant. Help with system tasks.',
})

const result = await agent.invoke('List the files in the current directory')
console.log(result.lastMessage)
```

## Custom Model Configuration

```typescript
import { Agent } from '@strands-agents/sdk'
import { BedrockModel } from '@strands-agents/sdk'

const model = new BedrockModel({
  modelId: 'anthropic.claude-sonnet-4-20250514-v1:0',
  region: 'us-west-2',
  temperature: 0.3,
})

const agent = new Agent({ model })
```

## Streaming Responses (for Web Servers)

```typescript
import { Agent } from '@strands-agents/sdk'

const agent = new Agent()

async function handleRequest(prompt: string) {
  for await (const event of agent.stream(prompt)) {
    console.log('Event:', event.type)
    // Forward events to client via SSE, WebSocket, etc.
  }
}
```

## Project Structure

```
my-agent/
├── src/
│   ├── agent.ts          # Agent definition and entrypoint
│   ├── tools/            # Custom tool definitions
│   │   ├── index.ts
│   │   └── lookup-order.ts
│   └── config.ts         # Model and environment config
├── package.json
├── tsconfig.json
├── .gitignore
└── README.md
```

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"]
}
```

## Running Locally

```bash
# Using tsx (recommended for dev)
npx tsx src/agent.ts

# Or compile and run
npx tsc && node dist/agent.js
```
