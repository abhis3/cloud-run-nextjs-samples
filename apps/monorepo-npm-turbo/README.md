# `monorepo-npm-turbo` — Turborepo + npm Workspaces Monorepo

## Overview

`monorepo-npm-turbo` is a multi-package **Turborepo + npm workspaces** monorepo containing:

- `apps/web`: Next.js 16 (`16.4.3`) application importing `@repo/ui` and guarding `/dashboard` with `apps/web/proxy.ts`.
- `packages/ui`: Shared internal workspace package (`@repo/ui`).

When built with `GOOGLE_BUILDABLE=apps/web`:

1. `google.nodejs.webturborepo` and `google.nodejs.webnextjs` opt in.
2. `webnextjs` sets `NEXT_PRIVATE_OUTPUT_TRACE_ROOT=/workspace` so Next.js traces workspace dependencies (`packages/ui`) from the monorepo root, producing `apps/web/.next/standalone/apps/web/server.js`.
3. `google.nodejs.npm` installs dependencies and runs `turbo run build --filter=web --env-mode=loose`.
4. `google.nodejs.webbundle` merges `apps/web/.next/static` and `apps/web/public` into `apps/web/.next/standalone/apps/web/`, prunes `/workspace`, and sets the start command to `node .cloudrun/serve.js`.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware buildpacks (`webturborepo`, `webnextjs`, `webbundle`). |
| `GOOGLE_BUILDABLE` | `apps/web` | Relative path from the monorepo root to the target Next.js application. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Prunes `/workspace` to the standalone trace (`~59 MiB`). |

## Expected Build & Runtime Results

- Start command: `node .cloudrun/serve.js`
- Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`

| Route | Status | Guarded? | Expected `Cache-Control` / Headers | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | `200` | No | `s-maxage=31536000, max-age=0` | Renders `Monorepo Web` and `Hello from @repo/ui workspace package!`. |
| `GET /about` | `200` | No | `s-maxage=31536000, max-age=0` | Renders `Monorepo About`. |
| `GET /dashboard` | `200` | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (`x-monorepo-proxy: 1`) | Guarded by `apps/web/proxy.ts`. |
