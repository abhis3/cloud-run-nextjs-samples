# `config-conditional-routes` (Known Gap)

Minimal Next.js 16.4 sample **without `proxy.ts` / `middleware.ts`** that uses `next.config.mjs` `rewrites()` and `headers()` with `has` / `missing` (`header` and `cookie`) conditions to route a single URL path to different static (SSG) content.

## What This Sample Covers (Known Gap)

- **Configuration**:
  - No `proxy.ts` or `middleware.ts` is present (`routing.middlewareMatchers` in `.cloudrun/next-routing.json` is `[]`).
  - `next.config.mjs` defines `beforeFiles` rewrites and custom headers using `has` and `missing` rules:
    - `GET /pricing` with header `x-tier: enterprise` rewrites to `/pricing-enterprise` and sets `x-pricing-variant: enterprise`; without the header it serves `/pricing`.
    - `GET /offer` with cookie `tier=vip` rewrites to `/banner-vip` and sets `x-offer-variant: vip`; when `tier=vip` is missing it rewrites to `/banner-default`.
- **Known Gap**:
  - Today's `.cloudrun/serve.js` runtime cache guard only inspects `proxy.ts` / `middleware.ts` matchers (`isGuarded` returns `false` when `middlewareMatchers` is empty or does not match).
  - Because `next.config.mjs` `has`/`missing` rewrites and headers are not treated as guarded routes, responses for `/pricing` and `/offer` retain `Cache-Control: s-maxage=31536000, max-age=0`.
  - Behind a shared CDN (such as Cloud CDN with `USE_ORIGIN_HEADERS`) that does not include `x-tier` or `Cookie` in the cache key, the first response cached for `/pricing` or `/offer` would be served to subsequent visitors regardless of their headers or cookies.
  - These expectations are marked `"mode": "known-gap"` in `expectations.json` so `scripts/verify.mjs` reports them separately without failing the test suite.

## Workaround

If a route's content varies by request headers or cookies, either:
1. Gate the route with `proxy.ts` (so `.cloudrun/serve.js` clamps `Cache-Control` to `private, no-cache, no-store, max-age=0, must-revalidate`), or
2. Explicitly set `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` in `next.config.mjs` `headers()` for the affected `source` path.

## Build Environment Variables

| Variable | Value | Purpose |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Cloud Run buildpacks (`ALPHA` track) |
| `GOOGLE_WEB_PRUNE` | `true` (optional) | Prunes image to standalone runtime and sets `google.web-serve-mode=standalone` |

## Routes & Expected Results

| Route | Request Headers | Content Served | Current `Cache-Control` | Verification Mode |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | None | `Config Conditional Routes Home` | `s-maxage=31536000, max-age=0` | `pass` |
| `GET /pricing` | None | `Standard Pricing Tier` | `s-maxage=31536000, max-age=0` | `known-gap` |
| `GET /pricing` | `x-tier: enterprise` | `Enterprise Pricing Tier` (`x-pricing-variant: enterprise`) | `s-maxage=31536000, max-age=0` | `known-gap` |
| `GET /offer` | None | `Default Public Banner` | `s-maxage=31536000, max-age=0` | `known-gap` |
| `GET /offer` | `Cookie: tier=vip` | `VIP Member Banner` (`x-offer-variant: vip`) | `s-maxage=31536000, max-age=0` | `known-gap` |
