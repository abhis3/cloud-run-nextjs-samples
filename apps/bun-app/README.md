# `bun-app` — Next.js 16 with Bun (`bun.lock`)

## Overview

`bun-app` tests framework-aware Next.js builds when the project uses **Bun** (`bun.lock` text lockfile) as its package manager:

- `google.nodejs.webnextjs` resolves the Next.js version directly from `bun.lock` (`nodejs.BunLockVersion`) to verify the `>= 16.3.5 < 17.0.0` version gate.
- `google.nodejs.bun` installs dependencies and runs `bun run build` with the `@google-cloud/adapter-nextjs` environment variables (`NEXT_ADAPTER_PATH`, `NEXT_PRIVATE_OUTPUT_TRACE_ROOT`, `GOOGLE_WEB_ADAPTER_ACTIVE=true`).
- `google.nodejs.webbundle` prunes `/workspace` and configures `node .cloudrun/serve.js`.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Enables standalone workspace pruning. |

## Expected Build Output

- Participating buildpacks: `google.nodejs.runtime`, `google.nodejs.webnextjs`, `google.nodejs.bun`, `google.nodejs.webbundle`
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
