import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const res = NextResponse.next();
  res.headers.set('x-edge-middleware', '1');
  res.headers.set('CDN-Cache-Control', 'public, max-age=3600');
  res.headers.set('Surrogate-Control', 'max-age=3600');
  return res;
}

export const config = {
  matcher: ['/dashboard/:path*'],
};
