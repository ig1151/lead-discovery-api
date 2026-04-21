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
