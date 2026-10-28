# `esm-root-app` — Root `"type": "module"` Package Isolation

## Overview

`esm-root-app` tests a Next.js 16 application whose root `package.json` sets `"type": "module"` and uses an ESM `next.config.js` (`export default nextConfig`).

Because `.cloudrun/serve.js` is bundled as a CommonJS entrypoint (`require(...)`), `@google-cloud/adapter-nextjs` writes `.cloudrun/package.json` with `{"type": "commonjs"}` alongside `.cloudrun/serve.js`. This isolates `.cloudrun/serve.js` from the application's `"type": "module"` root `package.json` so `node .cloudrun/serve.js` boots cleanly without `ReferenceError: require is not defined in ES module scope`.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Enables standalone workspace pruning. |

## Expected Build Output

- `.cloudrun/package.json` contains `{"type": "commonjs"}`
- Start command: `node .cloudrun/serve.js`
- Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`

## Expected Runtime & Cache-Guard Results

| Route | Status | Guarded? | Expected `Cache-Control` / Headers |
| :--- | :--- | :--- | :--- |
| `GET /` | `200` | No | `s-maxage=31536000, max-age=0` |
| `GET /about` | `200` | No | `s-maxage=31536000, max-age=0` (`x-about-header: 1`) |
| `GET /dashboard` | `200` | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (`x-proxy-ran: 1`) |
| `GET /blog/a` | `200` | No | `s-maxage=60, stale-while-revalidate=..., max-age=0` |
| `GET /legacy` | `200` | No | `200 OK` (`Pages Router Legacy Page`) |
| `GET /api/legacy-api` | `200` | No | `200 OK` (`{"legacy":true}`) |
| `GET /robots.txt` | `200` | No | `200 OK` (`User-agent: *`) |
| `GET /_next/image?url=%2Flogo.png&w=32&q=75` | `200` | No | `Content-Type: image/webp` |
