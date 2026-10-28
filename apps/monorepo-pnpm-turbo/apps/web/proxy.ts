import { NextResponse } from 'next/server';
export function proxy() {
  const res = NextResponse.next();
  res.headers.set('x-monorepo-proxy', '1');
  return res;
}
export const config = {
  matcher: ['/dashboard/:path*'],
};
