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
