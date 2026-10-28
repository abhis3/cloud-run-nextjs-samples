# `yarn1-app` — Next.js 16 with Yarn Classic (`yarn.lock` v1)

## Overview

`yarn1-app` tests framework-aware Next.js builds with **Yarn 1 (`yarn.lock`)** and standard `"scripts": { "build": "next build", "start": "next start" }` (no `gcp-build` script required):

- When `GOOGLE_WEB_ADAPTER_ACTIVE=true` is exported by `google.nodejs.webnextjs`, `google.nodejs.yarn` runs `yarn run build` automatically even without a `gcp-build` script.
- `google.nodejs.yarn` installs `node_modules` in `/workspace/node_modules` without exporting a duplicate `/layers/google.nodejs.yarn/yarn_modules` launch layer, so `google.nodejs.webbundle` can prune `/workspace` cleanly when `GOOGLE_WEB_PRUNE=true`.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Enables standalone workspace pruning. |

## Expected Build Output

- Participating buildpacks: `google.nodejs.runtime`, `google.nodejs.webnextjs`, `google.nodejs.yarn`, `google.nodejs.webbundle`
- Start command: `node .cloudrun/serve.js`
- Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`
- No `/layers/google.nodejs.yarn/yarn_modules` layer in the final image.

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
