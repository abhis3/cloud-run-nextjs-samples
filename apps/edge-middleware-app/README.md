# `edge-middleware-app` — Legacy `middleware.ts` (Edge Runtime) + CDN Header Stripping

## Overview

`edge-middleware-app` tests a Next.js 16 (`16.4.3`) application that uses the legacy `middleware.ts` convention (instead of `proxy.ts`) targeting `/dashboard/:path*`. Inside `middleware.ts`, the handler sets `x-edge-middleware: 1` and attempts to attach upstream CDN cache headers (`CDN-Cache-Control: public, max-age=3600` and `Surrogate-Control: max-age=3600`).

This sample verifies that `.cloudrun/serve.js` inspects `routing.middlewareMatchers` from `.cloudrun/next-routing.json`, clamps `Cache-Control` to `private, no-cache, no-store, max-age=0, must-revalidate`, and strips all CDN-specific cache headers (`CDN-Cache-Control`, `Cloudflare-CDN-Cache-Control`, `Vercel-CDN-Cache-Control`, `Surrogate-Control`) on matched routes.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Enables standalone workspace pruning. |

## Expected Build Output

- Start command: `node .cloudrun/serve.js`
- Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`

## Expected Runtime & Cache-Guard Results

| Route | Status | Guarded? | Expected `Cache-Control` / Headers | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | `200` | No | `s-maxage=31536000, max-age=0` | Static home page; `next/image` renders a plain `<img src="/logo.png">` (no `/_next/image` URL). |
| `GET /about` | `200` | No | `s-maxage=31536000, max-age=0` | Unguarded static page. |
| `GET /dashboard` | `200` | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (`x-edge-middleware: 1`) | `CDN-Cache-Control` and `Surrogate-Control` set by `middleware.ts` are stripped by `serve.js`. |
| `GET /blog/a` | `200` | No | `s-maxage=60, stale-while-revalidate=..., max-age=0` | Unguarded ISR route. |
| `GET /legacy` | `200` | No | `private, no-cache, no-store, max-age=0, must-revalidate` | Pages Router page. |
| `GET /api/legacy-api` | `200` | No | JSON `{"legacy":true}` | Pages Router API route. |
| `GET /logo.png` | `200` | No | `Content-Type: image/png` | Original image from `public/`. |
| `GET /_next/image?url=%2Flogo.png&w=32&q=75` | `404` | No | 404 response | Next.js image optimization is off by default (`images.unoptimized: true`). |
| `GET /does-not-exist-404` | `404` | No | 404 response | Non-existent route. |
| `GET /throw-pages` | `500` | No | 500 response | Pages Router 500 error page. |
| `GET /throw-app` | `500` | No | 500 response | App Router 500 error boundary. |
