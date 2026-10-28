# `proxy-matchers`

Minimal Next.js 16.4 sample testing **`proxy.ts` `config.matcher` entries with `has` and `missing` conditions** (`header`, `cookie`, and `query`) in front of SSG and ISR pages.

## What This Sample Covers

- **Fail-closed conditional matcher stripping (`@google-cloud/adapter-nextjs`)**:
  - During `onBuildComplete`, `@google-cloud/adapter-nextjs` strips `has` and `missing` arrays from `routing.middlewareMatchers` and `middleware.matchers` when writing `.cloudrun/next-routing.json`.
  - Why: If a path only runs `proxy.ts` when a specific cookie, header, or query parameter is present (or absent), allowing an unconditioned request on that same URL to be stored in a shared CDN with `s-maxage` would poison the cache for subsequent conditioned requests (or vice versa).
  - Consequently, `.cloudrun/serve.js` guards every path matched by `sourceRegex` **whether or not** the `has`/`missing` condition holds on a particular request.
- **Unmatched routes**:
  - Routes not matching any `proxy.ts` `sourceRegex` (`/` and `/public-isr`) remain unguarded and keep their `s-maxage` directives (with `max-age=0` appended).

## Build Environment Variables

| Variable | Value | Purpose |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Cloud Run buildpacks (`ALPHA` track) |
| `GOOGLE_WEB_PRUNE` | `true` (optional) | Prunes image to standalone runtime and sets `google.web-serve-mode=standalone` |

## Routes & Expected Results

| Route | Request Condition | `proxy.ts` Runs? | Guarded? | Expected `Cache-Control` |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | None (SSG) | No | No | `s-maxage=31536000, max-age=0` |
| `GET /public-isr` | None (ISR, `revalidate = 60`) | No | No | `s-maxage=60, stale-while-revalidate=31535940, max-age=0` |
| `GET /header-gated` | Header `x-custom-header: enabled` | **Yes** (`x-proxy-ran: 1`) | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (all 4 CDN headers stripped) |
| `GET /header-gated` | No `x-custom-header` | No | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /cookie-gated` | No `bypass_proxy=1` cookie | **Yes** (`x-proxy-ran: 1`) | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (all 4 CDN headers stripped) |
| `GET /cookie-gated` | `Cookie: bypass_proxy=1` | No | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` |
| `GET /query-gated?draft=true` | Query `draft=true` | **Yes** (`x-proxy-ran: 1`) | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (all 4 CDN headers stripped) |
| `GET /query-gated` | No query string | No | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` |
