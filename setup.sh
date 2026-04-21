#!/bin/bash
set -e

echo "🚀 Setting up Lead Discovery API..."

mkdir -p src/routes src/discovery

cat > package.json << 'ENDPACKAGE'
{
  "name": "lead-discovery-api",
  "version": "1.0.0",
  "description": "AI-powered lead discovery API — find companies and contacts matching any query, industry or hiring signal.",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "helmet": "^7.1.0",
    "joi": "^17.11.0"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.2"
  }
}
ENDPACKAGE

cat > tsconfig.json << 'ENDTSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
ENDTSCONFIG

cat > render.yaml << 'ENDRENDER'
services:
  - type: web
    name: lead-discovery-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 10000
      - key: ANTHROPIC_API_KEY
        sync: false
      - key: TAVILY_API_KEY
        sync: false
ENDRENDER

cat > .gitignore << 'ENDGITIGNORE'
node_modules/
dist/
.env
*.log
ENDGITIGNORE

cat > src/logger.ts << 'ENDLOGGER'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
ENDLOGGER

cat > src/discovery/search.ts << 'ENDSEARCH'
import axios from 'axios';

export async function tavilySearch(query: string, maxResults = 10): Promise<Array<{ title: string; url: string; content: string }>> {
  const apiKey = process.env.TAVILY_API_KEY;
  if (!apiKey) throw new Error('TAVILY_API_KEY not set');

  const res = await axios.post(
    'https://api.tavily.com/search',
    { query, max_results: maxResults, search_depth: 'basic', include_raw_content: false },
    {
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    }
  );

  return (res.data.results ?? []).map((r: { title: string; url: string; content?: string }) => ({
    title: r.title,
    url: r.url,
    content: r.content ?? '',
  }));
}
ENDSEARCH

cat > src/discovery/claude.ts << 'ENDCLAUDE'
import axios from 'axios';

const ANTHROPIC_API = 'https://api.anthropic.com/v1/messages';

export async function claudeExtractLeads(content: string, query: string, limit: number): Promise<unknown> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');

  const prompt = `You are a lead generation expert. Based on the search results below, extract company leads matching this query: "${query}"

Return ONLY a valid JSON array of up to ${limit} leads. Each lead must have:
{
  "company": "company name",
  "website": "domain only e.g. stripe.com",
  "description": "one sentence description",
  "industry": "industry name",
  "location": "city, country or null",
  "size": "employee range or null",
  "hiring": true or false based on signals,
  "signals": ["reason this is a good lead"],
  "contact_hint": "likely contact email pattern or null"
}

Rules:
- Only include real companies with clear web presence
- Extract from the search results only — do not hallucinate
- Return only the JSON array, no markdown or explanation

Search results:
${content}`;

  const res = await axios.post(
    ANTHROPIC_API,
    {
      model: 'claude-sonnet-4-20250514',
      max_tokens: 2000,
      messages: [{ role: 'user', content: prompt }],
    },
    {
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      timeout: 30000,
    }
  );

  const text = res.data.content[0]?.text ?? '[]';
  try {
    return JSON.parse(text.replace(/```json|```/g, '').trim());
  } catch {
    return [];
  }
}
ENDCLAUDE

cat > src/discovery/runner.ts << 'ENDRUNNER'
import { tavilySearch } from './search';
import { claudeExtractLeads } from './claude';

export interface Lead {
  company: string;
  website: string | null;
  description: string;
  industry: string;
  location: string | null;
  size: string | null;
  hiring: boolean;
  signals: string[];
  contact_hint: string | null;
}

export interface LeadDiscoveryResult {
  query: string;
  leads: Lead[];
  count: number;
  sources: string[];
  latency_ms: number;
  timestamp: string;
}

export async function discoverLeads(
  query: string,
  limit = 10,
  filters?: { industry?: string; location?: string; hiring?: boolean }
): Promise<LeadDiscoveryResult> {
  const start = Date.now();

  // Build enriched search query
  const searchParts = [query];
  if (filters?.industry) searchParts.push(filters.industry);
  if (filters?.location) searchParts.push(filters.location);
  if (filters?.hiring) searchParts.push('hiring jobs careers');

  const searchQuery = searchParts.join(' ');

  // Run multiple searches in parallel for better coverage
  const [generalResults, linkedinResults] = await Promise.all([
    tavilySearch(`${searchQuery} companies list`, 8),
    tavilySearch(`${searchQuery} site:linkedin.com/company`, 5),
  ]);

  const allResults = [...generalResults, ...linkedinResults];
  const sources = [...new Set(allResults.map(r => r.url))].slice(0, 10);

  const content = allResults
    .map(r => `Title: ${r.title}\nURL: ${r.url}\nContent: ${r.content}`)
    .join('\n\n')
    .slice(0, 15000);

  const raw = await claudeExtractLeads(content, query, limit) as Lead[];

  // Apply filters
  let leads = Array.isArray(raw) ? raw : [];
  if (filters?.hiring === true) {
    leads = leads.filter(l => l.hiring === true);
  }
  if (filters?.industry) {
    const ind = filters.industry.toLowerCase();
    leads = leads.filter(l => l.industry?.toLowerCase().includes(ind) || l.description?.toLowerCase().includes(ind));
  }
  if (filters?.location) {
    const loc = filters.location.toLowerCase();
    leads = leads.filter(l => l.location?.toLowerCase().includes(loc));
  }

  return {
    query,
    leads: leads.slice(0, limit),
    count: Math.min(leads.length, limit),
    sources,
    latency_ms: Date.now() - start,
    timestamp: new Date().toISOString(),
  };
}
ENDRUNNER

cat > src/routes/leads.ts << 'ENDLEADS'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { discoverLeads } from '../discovery/runner';
import { logger } from '../logger';

const router = Router();

const schema = Joi.object({
  query: Joi.string().min(2).max(300).required(),
  limit: Joi.number().integer().min(1).max(20).default(10),
  filters: Joi.object({
    industry: Joi.string().max(100).optional(),
    location: Joi.string().max(100).optional(),
    hiring: Joi.boolean().optional(),
  }).optional(),
});

router.post('/leads/find', async (req: Request, res: Response) => {
  const { error, value } = schema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Validation failed', details: error.details[0].message });
    return;
  }

  logger.info({ query: value.query, limit: value.limit }, 'Lead discovery started');

  try {
    const result = await discoverLeads(value.query, value.limit, value.filters);
    logger.info({ query: value.query, count: result.count, latency_ms: result.latency_ms }, 'Lead discovery complete');
    res.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Discovery failed';
    logger.error({ query: value.query, err }, 'Lead discovery failed');
    res.status(500).json({ error: 'Lead discovery failed', details: message });
  }
});

export default router;
ENDLEADS

cat > src/routes/docs.ts << 'ENDDOCS'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Lead Discovery API</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; background: #0f0f0f; color: #e0e0e0; }
    h1 { color: #7c3aed; } h2 { color: #a78bfa; border-bottom: 1px solid #333; padding-bottom: 8px; }
    pre { background: #1a1a1a; padding: 16px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
    code { color: #c084fc; }
    .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; margin-right: 8px; color: white; }
    .post { background: #7c3aed; } .get { background: #065f46; }
    table { width: 100%; border-collapse: collapse; } td, th { padding: 8px 12px; border: 1px solid #333; text-align: left; }
    th { background: #1a1a1a; }
  </style>
</head>
<body>
  <h1>Lead Discovery API</h1>
  <p>AI-powered lead discovery — find companies and contacts matching any query, industry or hiring signal.</p>
  <h2>Endpoints</h2>
  <table>
    <tr><th>Method</th><th>Path</th><th>Description</th></tr>
    <tr><td><span class="badge post">POST</span></td><td>/v1/leads/find</td><td>Discover leads matching a query</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/health</td><td>Health check</td></tr>
  </table>
  <h2>Example</h2>
  <pre>POST /v1/leads/find
{
  "query": "AI startups hiring engineers",
  "limit": 10,
  "filters": {
    "industry": "AI",
    "location": "San Francisco",
    "hiring": true
  }
}</pre>
  <p><a href="/openapi.json" style="color:#a78bfa">OpenAPI JSON</a></p>
</body>
</html>`);
});

export default router;
ENDDOCS

cat > src/routes/openapi.ts << 'ENDOPENAPI'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: {
      title: 'Lead Discovery API',
      version: '1.0.0',
      description: 'AI-powered lead discovery API — find companies and contacts matching any query, industry or hiring signal.',
    },
    servers: [{ url: 'https://lead-discovery-api.onrender.com' }],
    paths: {
      '/v1/leads/find': {
        post: {
          summary: 'Discover leads matching a query',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['query'],
                  properties: {
                    query: { type: 'string' },
                    limit: { type: 'integer', default: 10 },
                    filters: {
                      type: 'object',
                      properties: {
                        industry: { type: 'string' },
                        location: { type: 'string' },
                        hiring: { type: 'boolean' },
                      },
                    },
                  },
                },
              },
            },
          },
          responses: { '200': { description: 'Lead discovery results' } },
        },
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } },
      },
    },
  });
});

export default router;
ENDOPENAPI

cat > src/index.ts << 'ENDINDEX'
import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import leadsRouter from './routes/leads';
import docsRouter from './routes/docs';
import openapiRouter from './routes/openapi';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());
app.use(rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false }));

app.get('/', (_req, res) => {
  res.json({
    service: 'lead-discovery-api',
    version: '1.0.0',
    description: 'AI-powered lead discovery API.',
    status: 'ok',
    docs: '/docs',
    health: '/v1/health',
    endpoints: {
      find_leads: 'POST /v1/leads/find',
    },
  });
});

app.get('/v1/health', (_req, res) => {
  res.json({ status: 'ok', service: 'lead-discovery-api', timestamp: new Date().toISOString() });
});

app.use('/v1', leadsRouter);
app.use('/docs', docsRouter);
app.use('/openapi.json', openapiRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Lead Discovery API running');
});
ENDINDEX

echo "✅ All files created!"
echo "Next: npm install && npm run dev"