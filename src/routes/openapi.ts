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
