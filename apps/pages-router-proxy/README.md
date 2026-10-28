# `pages-router-proxy`

Minimal Next.js 16.4 sample testing **Pages Router SSG/ISR pages and API routes gated by `proxy.ts`**, including **`/_next/data/<buildId>/...json`** client-navigation data requests.

## What This Sample Covers

- **Pages Router SSG (`getStaticProps`) & ISR (`getStaticProps` with `revalidate: 60`)**:
  - `pages/index.tsx` and `pages/public-isr.tsx` are unguarded static/ISR pages.
  - `pages/guarded-ssg.tsx` and `pages/guarded-isr.tsx` are gated by `proxy.ts`.
- **`/_next/data/<buildId>/<page>.json` Normalization**:
  - When a Pages Router application navigates client-side via `next/link` or `next/router`, Next.js fetches `/_next/data/<buildId>/<page>.json` instead of `/<page>` and invokes `proxy.ts` on that request.
  - `.cloudrun/serve.js` normalizes `/_next/data/<buildId>/<page>.json` back to `/<page>` before checking `routing.middlewareMatchers`, ensuring data JSON responses for guarded Pages Router routes also get `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` and have CDN headers stripped.
- **Pages Router API Routes (`pages/api/*`)**:
  - `pages/api/guarded-api.ts` sets `Cache-Control: public, s-maxage=300` and `CDN-Cache-Control: public, max-age=600` in the handler, and is matched by `proxy.ts` -> `.cloudrun/serve.js` overrides `Cache-Control` to `private, no-cache, no-store, max-age=0, must-revalidate` and strips `CDN-Cache-Control`.
  - `pages/api/public-api.ts` is not matched by `proxy.ts` -> retains `s-maxage=120` with `max-age=0` appended.

## Build Environment Variables

| Variable | Value | Purpose |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Cloud Run buildpacks (`ALPHA` track) |
| `GOOGLE_WEB_PRUNE` | `true` (optional) | Prunes image to standalone runtime and sets `google.web-serve-mode=standalone` |

## Routes & Expected Results

| Route | Guarded? | Expected Status | Expected `Cache-Control` |
| :--- | :--- | :--- | :--- |
| `GET /` | No | `200` | `s-maxage=31536000, max-age=0` |
| `GET /_next/data/<buildId>/index.json` | No | `200` | `s-maxage=31536000, max-age=0` |
| `GET /public-isr` | No | `200` | `s-maxage=60, stale-while-revalidate, max-age=0` |
| `GET /guarded-ssg` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /_next/data/<buildId>/guarded-ssg.json` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /guarded-isr` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /_next/data/<buildId>/guarded-isr.json` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /api/guarded-api` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` (`CDN-Cache-Control` stripped) |
| `GET /api/public-api` | No | `200` | `public, s-maxage=120, max-age=0` |
