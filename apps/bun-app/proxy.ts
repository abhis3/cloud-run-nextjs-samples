import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function proxy(request: NextRequest) {
  const res = NextResponse.next();
  res.headers.set('x-proxy-ran', '1');
  return res;
}

export const config = {
  matcher: [
    '/dashboard/:path*',
    {
      source: '/guarded-has',
      has: [{ type: 'header', key: 'x-custom' }],
      missing: [{ type: 'cookie', key: 'bypass' }],
    },
  ],
};
