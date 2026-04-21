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
