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
