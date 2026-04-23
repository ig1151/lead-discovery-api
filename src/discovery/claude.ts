const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions';
const MODEL = 'anthropic/claude-sonnet-4-5';

export async function claudeExtractLeads(content: string, query: string, limit: number): Promise<unknown> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) throw new Error('OPENROUTER_API_KEY not set');

  const prompt = `You are a lead generation expert. Based on the search results below, extract company leads matching this query: "${query}"
Return ONLY a valid JSON array of up to ${limit} leads. Each lead must have exactly this structure:
{
  "company": "company name",
  "website": "domain only e.g. stripe.com",
  "description": "one sentence description",
  "industry": "industry name",
  "location": "city, country or null",
  "size": "employee range or null",
  "hiring": true or false,
  "signals": ["specific reason this is a good lead"],
  "confidence": 0.0 to 1.0 based on how confident you are this matches the query,
  "contact": {
    "name": "full name if found or null",
    "email": "email address if found or null",
    "role": "job title if found e.g. CEO, Founder, CTO or null"
  }
}
Rules:
- Only include real companies with clear web presence
- Extract contact info only if explicitly found in the search results
- confidence should reflect how well this lead matches the query
- Return only the JSON array, no markdown or explanation
Search results:
${content}`;

  const response = await fetch(OPENROUTER_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 2000,
      messages: [{ role: 'user', content: prompt }],
      response_format: { type: 'json_object' },
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenRouter error: ${response.status} ${err}`);
  }

  const data = await response.json() as { choices: { message: { content: string } }[] };
  const text = data.choices[0].message.content ?? '[]';
  try {
    const parsed = JSON.parse(text.replace(/```json|```/g, '').trim());
    return Array.isArray(parsed) ? parsed : (parsed.leads ?? parsed.companies ?? []);
  } catch {
    return [];
  }
}
