# `monorepo-pnpm-turbo` — Turborepo + pnpm Workspaces Monorepo

## Overview

`monorepo-pnpm-turbo` is a **Turborepo + pnpm workspaces** (`pnpm-lock.yaml`, `pnpm-workspace.yaml`) monorepo containing `apps/web` and `packages/ui` (`"@repo/ui": "workspace:*"`).

In addition to testing `google.nodejs.webturborepo` + `google.nodejs.pnpm` with `GOOGLE_BUILDABLE=apps/web`, this sample verifies that `google.nodejs.webbundle` preserves all internal `.pnpm` virtual-store symlinks inside `apps/web/.next/standalone/node_modules/.pnpm` when pruning `/workspace` (`GOOGLE_WEB_PRUNE=true`).

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware buildpacks (`webturborepo`, `webnextjs`, `webbundle`). |
| `GOOGLE_BUILDABLE` | `apps/web` | Relative path from the monorepo root to the target Next.js application. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Prunes `/workspace` while preserving `.pnpm` symlinks in the standalone output. |

## Expected Build & Runtime Results

- Start command: `node .cloudrun/serve.js`
- Image labels: `google.web-cache-guard=true`, `google.web-serve-mode=standalone`

| Route | Status | Guarded? | Expected `Cache-Control` / Headers | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET /` | `200` | No | `s-maxage=31536000, max-age=0` | Renders `Monorepo Web` and `Hello from @repo/ui workspace package!`. |
| `GET /about` | `200` | No | `s-maxage=31536000, max-age=0` | Renders `Monorepo About`. |
| `GET /dashboard` | `200` | **Yes** | `private, no-cache, no-store, max-age=0, must-revalidate` (`x-monorepo-proxy: 1`) | Guarded by `apps/web/proxy.ts`. |
