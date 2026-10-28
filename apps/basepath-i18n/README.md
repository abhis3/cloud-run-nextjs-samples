# `basepath-i18n`

Minimal Next.js 16.4 sample testing **`basePath` + Pages Router `i18n` routing** combined with **`proxy.ts` gating a Static Site Generation (SSG) page**.

## What This Sample Covers

- **`next.config.mjs`**: Configures `basePath: '/base'` and Pages Router `i18n` (`locales: ['en', 'fr', 'de']`, `defaultLocale: 'en'`, `localeDetection: false`).
- **Pages Router SSG (`getStaticProps`)**:
  - `pages/index.tsx` and `pages/about.tsx` are unguarded static pages rendered for each locale.
  - `pages/dashboard/index.tsx` is a static (`getStaticProps`) page gated by `proxy.ts` (`matcher: ['/dashboard/:path*']`).
- **Runtime Cache Guard (`.cloudrun/serve.js`)**:
  - Strips `basePath` (`/base`), `/_next/data/<buildId>/...json` wrappers, and locale prefixes (`/en`, `/fr`, `/de`) when evaluating whether `proxy.ts` can run on a request.
  - Forces `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` and strips CDN cache headers (`CDN-Cache-Control`, `Cloudflare-CDN-Cache-Control`, `Vercel-CDN-Cache-Control`, `Surrogate-Control`) on every proxied path under `/base` and every locale prefix (including `/_next/data/<buildId>/<locale>/dashboard.json`).
  - Preserves `s-maxage` (and appends `max-age=0`) on unguarded SSG pages.

## Build Environment Variables

| Variable | Value | Purpose |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Cloud Run buildpacks (`ALPHA` track) |
| `GOOGLE_WEB_PRUNE` | `true` (optional) | Prunes image to standalone runtime and sets `google.web-serve-mode=standalone` |

## Routes & Expected Results

| Route | Guarded? | Expected Status | Expected `Cache-Control` | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET /base` | No | `200` | `s-maxage=31536000, max-age=0` | Default locale (`en`) SSG home page |
| `GET /base/fr` | No | `200` | `s-maxage=31536000, max-age=0` | `fr` locale SSG home page |
| `GET /base/about` | No | `200` | `s-maxage=31536000, max-age=0` | Default locale (`en`) SSG about page |
| `GET /base/de/about` | No | `200` | `s-maxage=31536000, max-age=0` | `de` locale SSG about page |
| `GET /base/dashboard` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` | `x-proxy-ran: 1`, `CDN-Cache-Control` stripped |
| `GET /base/en/dashboard` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` | Explicit default locale `en` prefix guarded |
| `GET /base/fr/dashboard` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` | `fr` locale prefix guarded |
| `GET /base/de/dashboard` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` | `de` locale prefix guarded |
| `GET /base/_next/data/<buildId>/<locale>/dashboard.json` | **Yes** | `200` | `private, no-cache, no-store, max-age=0, must-revalidate` | Data routes for `en`, `fr`, `de` guarded |
