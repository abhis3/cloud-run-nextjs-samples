# `single-app` — Reference Hybrid App Router + Pages Router Next.js Application

## Overview

`single-app` is the reference Next.js 16 (`16.4.3`) sample application using `npm` (`package-lock.json`). It exercises:

- **App Router static & dynamic rendering**: `/` (static page importing `public/traced.json`), `/about` (static page with custom `next.config.mjs` response header), and `/dashboard` (`force-dynamic` route behind `proxy.ts`).
- **Incremental Static Regeneration (ISR)**: `/blog/[id]` (`revalidate = 60`, pre-rendered for `/blog/a` and `/blog/b`).
- **Next.js 16 `proxy.ts` CDN Cache Guard**: `proxy.ts` matches `/dashboard/:path*` and `/guarded-has` (with `has`/`missing` conditions) and sets `x-proxy-ran: 1`.
- **Hybrid Pages Router coexistence**: `/legacy` (`pages/legacy.tsx`), `/api/legacy-api` (`pages/api/legacy-api.ts`), and custom Pages Router error handling (`pages/_error.tsx`).
- **Error boundaries (404 & 500)**: `/does-not-exist-404` (404), `/throw-pages` (Pages Router 500), and `/throw-app` (App Router `error.tsx` 500).
- **`next/image` with image optimization off (the adapter's default)**: `/` renders the logo as a plain `<img src="/logo.png">`, `/logo.png` serves the original file, and `/_next/image` returns `404`. [`esm-root-app`](../esm-root-app) covers the `GOOGLE_NEXTJS_IMAGE_OPTIMIZATION=true` opt-in.
- **Untraced vs. traced runtime files**: `/api/hello` reads `data/secret.json` via a dynamically constructed path to demonstrate `GOOGLE_WEB_PRUNE=report-only` untraced-file hints vs. `outputFileTracingIncludes` (`NEXT_TEST_TRACING_INCLUDES=1`).

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Opts into the alpha framework-aware Next.js buildpacks (`google.nodejs.webnextjs` and `google.nodejs.webbundle`). |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Installs the packed `@google-cloud/adapter-nextjs` tarball into the build-only adapter layer until published to npm. |
| `GOOGLE_WEB_PRUNE` | `true` \| `report-only` \| `false` | `true` prunes `/workspace` to the standalone trace; `report-only` (default) logs prune savings and untraced files without pruning; `false` disables pruning. |
| `NEXT_TEST_TRACING_INCLUDES` | `1` *(optional)* | Enables `outputFileTracingIncludes: { '/api/hello': ['./data/**/*'] }` in `next.config.mjs` so `data/secret.json` is retained when `GOOGLE_WEB_PRUNE=true`. |

## Expected Build Output

- **When `GOOGLE_WEB_PRUNE=true`**:
  - Start command: `node .cloudrun/serve.js`
  - Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`
- **When `GOOGLE_WEB_PRUNE=report-only` (default) or `false`**:
  - Start command: `node .cloudrun/serve.js --project`
  - Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=project`

## Expected Runtime & Cache-Guard Results

| Route | Status | Guarded? | Expected `Cache-Control` / Headers | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | `200` | No | `s-maxage=31536000, max-age=0` | Renders `Home Page` and `{"tracedFromPublic":true}`; `next/image` renders a plain `<img src="/logo.png">` (no `/_next/image` URL). |
| `GET /about` | `200` | No | `s-maxage=31536000, max-age=0` (`x-about-header: 1`) | Unguarded static route keeps `s-maxage` and appends `max-age=0`. |
| `GET /dashboard` | `200` | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (`x-proxy-ran: 1`) | Guarded by `proxy.ts`; CDN cache headers stripped. |
| `GET /blog/a` | `200` | No | `s-maxage=60, stale-while-revalidate=..., max-age=0` | Unguarded ISR route keeps `s-maxage=60` and appends `max-age=0`. |
| `GET /legacy` | `200` | No | `private, no-cache, no-store, max-age=0, must-revalidate` | Pages Router page (`Pages Router Legacy Page`). |
| `GET /api/legacy-api` | `200` | No | Default API response headers | Returns `{"legacy":true}`. |
| `GET /robots.txt` | `200` | No | `public, max-age=0` | Static asset from `public/robots.txt`. |
| `GET /logo.png` | `200` | No | `Content-Type: image/png` | Original image from `public/`. |
| `GET /_next/image?url=%2Flogo.png&w=32&q=75` | `404` | No | 404 response | Next.js image optimization is off by default (`images.unoptimized: true`). |
| `GET /api/hello` | `200` | No | JSON `{"hello":"world","data":...}` | Returns `ENOENT` in `data` when pruned without `NEXT_TEST_TRACING_INCLUDES=1`, or `{"computedData":"secret-42"}` when traced/unpruned. |
| `GET /does-not-exist-404` | `404` | No | `private, no-cache, no-store, max-age=0, must-revalidate` | Next.js 404 page. |
| `GET /throw-pages` | `500` | No | `private, no-cache, no-store, max-age=0, must-revalidate` | Pages Router `pages/_error.tsx` 500 page. |
| `GET /throw-app` | `500` | No | `private, no-cache, no-store, max-age=0, must-revalidate` | App Router `app/throw-app/error.tsx` 500 boundary. |
