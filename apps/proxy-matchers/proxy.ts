import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function proxy(request: NextRequest) {
  const response = NextResponse.next();
  response.headers.set('x-proxy-ran', '1');
  response.headers.set('CDN-Cache-Control', 'public, max-age=86400');
  response.headers.set('Cloudflare-CDN-Cache-Control', 'public, max-age=86400');
  response.headers.set('Vercel-CDN-Cache-Control', 'public, max-age=86400');
  response.headers.set('Surrogate-Control', 'max-age=86400');
  return response;
}

export const config = {
  matcher: [
    {
      source: '/header-gated',
      has: [{ type: 'header', key: 'x-custom-header', value: 'enabled' }],
    },
    {
      source: '/cookie-gated',
      missing: [{ type: 'cookie', key: 'bypass_proxy', value: '1' }],
    },
    {
      source: '/query-gated',
      has: [{ type: 'query', key: 'draft', value: 'true' }],
    },
  ],
};
