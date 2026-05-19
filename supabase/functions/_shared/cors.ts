// Headers CORS partages entre toutes les Edge Functions du financement.
//
// Politique : pas de wildcard "*" en prod. Les origines autorisees sont :
//   1. Les origines statiques par defaut (avis-base.com + www)
//   2. L'env var SITE_URL si definie (ajoutee a la whitelist)
//   3. L'env var ALLOWED_ORIGINS (csv) si definie (REMPLACE la whitelist)
//
// L'origin de la request est "reflechi" dans Access-Control-Allow-Origin si
// elle figure dans la whitelist, sinon on retombe sur la premiere entree
// (https://avis-base.com par defaut). Le header Vary: Origin est ajoute pour
// que les caches CDN ne croisent pas les reponses entre origines.

const STATIC_ALLOWED = ['https://avis-base.com', 'https://www.avis-base.com'];

function getAllowedOrigins(): string[] {
  const explicit = Deno.env.get('ALLOWED_ORIGINS');
  if (explicit) {
    return explicit
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  }
  const siteUrl = Deno.env.get('SITE_URL');
  if (siteUrl && !STATIC_ALLOWED.includes(siteUrl)) {
    return [...STATIC_ALLOWED, siteUrl];
  }
  return STATIC_ALLOWED;
}

function pickOrigin(req?: Request): string {
  const allowed = getAllowedOrigins();
  if (!req) return allowed[0];
  const origin = req.headers.get('origin') || '';
  if (allowed.includes(origin)) return origin;
  return allowed[0];
}

function buildCorsHeaders(req?: Request): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': pickOrigin(req),
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  };
}

// Compat retro : certaines call sites importent encore `corsHeaders`
// directement. On le garde avec l'origine par defaut (jamais wildcard).
export const corsHeaders = buildCorsHeaders();

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: buildCorsHeaders(req) });
  }
  return null;
}

export function jsonResponse(body: unknown, status = 200, req?: Request): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...buildCorsHeaders(req), 'Content-Type': 'application/json' },
  });
}
