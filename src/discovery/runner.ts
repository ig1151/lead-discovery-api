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
  lead_score: number;
  contact_ready: boolean;
}

export interface LeadDiscoveryResult {
  query: string;
  leads: Lead[];
  count: number;
  sources: string[];
  latency_ms: number;
  timestamp: string;
}

function scoreLead(lead: Lead): number {
  let score = 50;
  if (lead.hiring) score += 15;
  if (lead.contact_hint) score += 10;
  if (lead.location) score += 5;
  if (lead.size) score += 5;
  if (lead.website) score += 5;
  if (lead.signals.length >= 3) score += 10;
  const intentSignals = ['funding', 'launch', 'hiring', 'growth', 'raised', 'series', 'expanded'];
  const signalText = lead.signals.join(' ').toLowerCase();
  for (const intent of intentSignals) {
    if (signalText.includes(intent)) { score += 5; break; }
  }
  return Math.min(score, 100);
}

function isContactReady(lead: Lead): boolean {
  return !!(lead.contact_hint && lead.website && lead.company);
}

export async function discoverLeads(
  query: string,
  limit = 10,
  filters?: { industry?: string; location?: string; hiring?: boolean; size?: string; role?: string }
): Promise<LeadDiscoveryResult> {
  const start = Date.now();
  const searchParts = [query];
  if (filters?.industry) searchParts.push(filters.industry);
  if (filters?.location) searchParts.push(filters.location);
  if (filters?.hiring) searchParts.push('hiring jobs careers');
  if (filters?.role) searchParts.push(filters.role);
  const searchQuery = searchParts.join(' ');
  const [generalResults, linkedinResults] = await Promise.all([
    tavilySearch(searchQuery + ' companies list', 8),
    tavilySearch(searchQuery + ' site:linkedin.com/company', 5),
  ]);
  const allResults = [...generalResults, ...linkedinResults];
  const sources = [...new Set(allResults.map(r => r.url))].slice(0, 10);
  const content = allResults.map(r => r.title + ' ' + r.url + ' ' + r.content).join(' ').slice(0, 15000);
  const raw = await claudeExtractLeads(content, query, limit) as Lead[];
  let leads = Array.isArray(raw) ? raw : [];
  if (filters?.hiring === true) leads = leads.filter(l => l.hiring === true);
  if (filters?.industry) {
    const ind = filters.industry.toLowerCase();
    leads = leads.filter(l => l.industry?.toLowerCase().includes(ind) || l.description?.toLowerCase().includes(ind));
  }
  if (filters?.location) {
    const loc = filters.location.toLowerCase();
    leads = leads.filter(l => l.location?.toLowerCase().includes(loc));
  }
  if (filters?.size) {
    leads = leads.filter(l => !l.size || l.size.includes(filters.size!));
  }
  leads = leads.map(l => ({ ...l, lead_score: scoreLead(l), contact_ready: isContactReady(l) }));
  leads.sort((a, b) => b.lead_score - a.lead_score);
  return {
    query,
    leads: leads.slice(0, limit),
    count: Math.min(leads.length, limit),
    sources,
    latency_ms: Date.now() - start,
    timestamp: new Date().toISOString(),
  };
}
