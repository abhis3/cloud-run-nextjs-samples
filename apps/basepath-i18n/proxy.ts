import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function proxy(request: NextRequest) {
  const response = NextResponse.next();
  response.headers.set('x-proxy-ran', '1');
  response.headers.set('CDN-Cache-Control', 'public, max-age=3600');
  return response;
}

export const config = {
  matcher: ['/dashboard/:path*'],
};
