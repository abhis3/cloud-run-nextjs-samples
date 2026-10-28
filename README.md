# Next.js Framework-Aware Cloud Run Build Samples

This repository contains sample Next.js 16 applications, automation scripts, and verification suites for testing **framework-aware Cloud Run source builds** powered by:

- **`@google-cloud/adapter-nextjs`** (from [`firebase/apphosting-adapters`](https://github.com/firebase/apphosting-adapters) `packages/@google-cloud/adapter-nextjs`), which configures `output: "standalone"`, emits `.cloudrun/bundle.yaml` (v2) and `.cloudrun/next-routing.json`, and bundles the `.cloudrun/serve.js` entrypoint with a fail-closed CDN cache guard.
- **Alpha-track Google Cloud Node.js Web Buildpacks** (`google.nodejs.webnextjs`, `google.nodejs.webturborepo`, `google.nodejs.webnx`, `google.nodejs.webbundle`, and `google.nodejs.websourcemaps` in [`GoogleCloudPlatform/buildpacks`](https://github.com/GoogleCloudPlatform/buildpacks)).

---

## Prerequisites

- **Node.js `>= 20`** (Node.js 22 LTS recommended) and `npm`, `pnpm`, `yarn` (v1), and `bun` for monorepo and package-manager samples.
- **Docker** and **[`pack` CLI](https://buildpacks.io/docs/for-platform-operators/how-to/integrate-ci/pack/) `>= 0.38.2`** (`0.40.10` recommended for Docker Engine 29+) for local buildpack testing.
- **[Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install)** with the `alpha` component installed (`gcloud components install alpha`) for Cloud Run source deployments.

---

## How to Opt In

Framework-aware Next.js builds are currently gated behind the **Alpha** release track and build-time environment variables:

1. **Use the `alpha` release track**:
   - When deploying to Cloud Run: use `gcloud alpha run deploy ... --source <app-dir>`.
   - When building locally with `pack`: pass `--env X_GOOGLE_RELEASE_TRACK=ALPHA`.
2. **Enable framework-aware builds (`GOOGLE_WEB_FRAMEWORKS=true`)**:
   - Pass `GOOGLE_WEB_FRAMEWORKS=true` in `--set-build-env-vars` (or `pack build --env`). When unset or `false`, all `google.nodejs.web*` buildpacks opt out and the standard generic Node.js build runs unchanged.
3. **Provide `@google-cloud/adapter-nextjs` (`GOOGLE_NEXTJS_ADAPTER_VERSION`)**:
   - Until `@google-cloud/adapter-nextjs` is published to the public npm registry, pack the adapter from `firebase/apphosting-adapters` (`origin/main`) into a `.tgz` inside the app directory using `./scripts/pack-adapter.sh <app-dir>` and set:
     ```text
     GOOGLE_NEXTJS_ADAPTER_VERSION=file:./google-cloud-adapter-nextjs-0.1.0.tgz
     ```
   - `google.nodejs.webnextjs` detects any value starting with `file:`, `/`, `./`, `../`, or ending with `.tgz` / `.tar.gz` and passes it directly to `npm install --prefix /layers/google.nodejs.webnextjs/web_nextjs_adapter <spec>` (executed from `/workspace`). Once published to npm, `GOOGLE_NEXTJS_ADAPTER_VERSION` can be omitted (defaulting to `0.1.0`) or set to a semver version/tag.
4. **Configure workspace pruning (`GOOGLE_WEB_PRUNE`)**:
   - `GOOGLE_WEB_PRUNE=report-only` *(default when unset)*: Runs `next build` with standalone tracing, logs how many files/bytes pruning would remove plus any untraced runtime data files outside `.next/standalone`, removes `.next/standalone`, sets label `google.web-serve-mode=project`, and boots via `node .cloudrun/serve.js --project`.
   - `GOOGLE_WEB_PRUNE=true`: Copies `.next/static` and `public` into `.next/standalone`, prunes `/workspace` down to only the standalone trace and `.cloudrun/` runtime files (~85–88% workspace size reduction), sets label `google.web-serve-mode=standalone`, and boots via `node .cloudrun/serve.js`.
   - `GOOGLE_WEB_PRUNE=false`: Disables pruning, removes `.next/standalone`, sets label `google.web-serve-mode=project`, and boots via `node .cloudrun/serve.js --project`.
5. **Monorepo target (`GOOGLE_BUILDABLE`)**:
   - For Turborepo (`turbo.json`) and Nx (`nx.json`) monorepos where the Next.js app lives in a subdirectory, pass `GOOGLE_BUILDABLE=apps/web`.

---

## Scripts & Workflows

### 1. Pack `@google-cloud/adapter-nextjs` from `origin/main`

[`scripts/pack-adapter.sh`](scripts/pack-adapter.sh) creates a temporary git worktree from `firebase/apphosting-adapters` (`origin/main`), builds `packages/@google-cloud/adapter-nextjs`, runs `npm pack`, and copies `google-cloud-adapter-nextjs-0.1.0.tgz` into one or more sample app directories:

```bash
# Pack and copy into a single sample app
./scripts/pack-adapter.sh apps/single-app

# Pack and copy into all apps/* directories
./scripts/pack-adapter.sh --all
```

*(Note: `*.tgz` is listed in the root `.gitignore` so packed tarballs inside `apps/<name>/` are not committed to git, while still being uploaded by `gcloud alpha run deploy --source apps/<name>` and staged by `./scripts/local-pack.sh`.)*

### 2. Local Testing with `pack`

[`scripts/local-pack.sh`](scripts/local-pack.sh) stages the target sample app (excluding local `node_modules` and `.next`), sets `X_GOOGLE_RELEASE_TRACK=ALPHA`, `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_NEXTJS_ADAPTER_VERSION=file:./google-cloud-adapter-nextjs-0.1.0.tgz`, `GOOGLE_WEB_PRUNE=true` (configurable via `--prune=<mode>`), and any app-specific `buildEnv` from `expectations.json`.

By default, `local-pack.sh` uses `gcr.io/buildpacks/builder:latest` (which will include the web buildpacks once released). To test against a builder image you built locally, pass `--builder <image>`:

```bash
./scripts/pack-adapter.sh apps/single-app

# Using the default public builder (once released):
./scripts/local-pack.sh apps/single-app

# Using a locally built builder image:
./scripts/local-pack.sh apps/single-app --builder my-local-builder:latest
```

Run the resulting container locally:

```bash
docker run -d --rm --name nextjs-sample -p 18080:8080 -e PORT=8080 fab-sample-single-app:latest
```

### 3. Deploying to Cloud Run

Use [`scripts/deploy.sh`](scripts/deploy.sh) to deploy a sample app from source via `gcloud alpha run deploy`:

```bash
./scripts/pack-adapter.sh apps/single-app
./scripts/deploy.sh nextjs-single-app apps/single-app us-central1 --prune=true
```

Under the hood, `scripts/deploy.sh` runs:

```bash
gcloud alpha run deploy nextjs-single-app \
  --source apps/single-app \
  --region us-central1 \
  --allow-unauthenticated \
  --set-build-env-vars=GOOGLE_WEB_FRAMEWORKS=true,GOOGLE_NEXTJS_ADAPTER_VERSION=file:./google-cloud-adapter-nextjs-0.1.0.tgz,GOOGLE_WEB_PRUNE=true
```

### 4. Verifying HTTP Routes, Cache Guard & Image Metadata

Use [`scripts/verify.mjs`](scripts/verify.mjs) to verify a running container or Cloud Run service URL against the app's `expectations.json`:

```bash
# Verify HTTP routes + Cache-Control guard against a local container or Cloud Run URL
node ./scripts/verify.mjs apps/single-app http://127.0.0.1:18080

# Also verify container image labels and stripped files (.js.map)
node ./scripts/verify.mjs apps/single-app http://127.0.0.1:18080 --image=fab-sample-single-app:latest
```

---

## Sample Applications & Test Matrix

| App | Package Manager / Tooling | Key Build Env Vars | What It Covers | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| [`apps/single-app`](apps/single-app) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Hybrid App Router + Pages Router, `proxy.ts` guard on `/dashboard`, ISR (`/blog/a`), `next/image` (`sharp`), 404/500 error boundaries, untraced vs. traced runtime files (`/api/hello`). | **Pass**: `/dashboard` guarded (`private, no-cache, no-store, max-age=0, must-revalidate`, CDN headers stripped); `/about` & `/blog/a` keep `s-maxage` + `max-age=0`; labels `google.web-cache-guard=true`, `google.web-serve-mode=standalone`. |
| [`apps/edge-middleware-app`](apps/edge-middleware-app) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Legacy `middleware.ts` (Edge runtime) setting `x-edge-middleware: 1`, `CDN-Cache-Control`, and `Surrogate-Control` on `/dashboard/:path*`. | **Pass**: `/dashboard` guarded (`private, no-cache, no-store, max-age=0, must-revalidate`) and `CDN-Cache-Control` / `Surrogate-Control` stripped. |
| [`apps/bun-app`](apps/bun-app) | `bun` (`bun.lock`) | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Next.js version resolution from `bun.lock`, `bun run build` execution, and standalone pruning. | **Pass**: Builds with `google.nodejs.bun`, prunes to standalone, and passes all HTTP & guard checks. |
| [`apps/yarn1-app`](apps/yarn1-app) | `yarn` v1 (`yarn.lock`) | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Yarn Classic build without `gcp-build` script and without a duplicate `yarn_modules` layer so `webbundle` prunes `/workspace`. | **Pass**: Builds with `google.nodejs.yarn`, prunes `/workspace`, and passes all HTTP & guard checks. |
| [`apps/esm-root-app`](apps/esm-root-app) | `npm` (`"type": "module"`) | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Root `package.json` with `"type": "module"` and ESM `next.config.js`; verifies `.cloudrun/package.json` (`{"type":"commonjs"}`) isolates `.cloudrun/serve.js`. | **Pass**: `node .cloudrun/serve.js` boots cleanly without ESM/CJS conflicts and passes all HTTP & guard checks. |
| [`apps/export-app`](apps/export-app) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Static export (`output: 'export'` in `next.config.mjs`). | **Pass (Stand-down)**: Adapter preserves `output: 'export'`; `webbundle` logs warning and skips standalone bundle without failing the build. |
| [`apps/custom-server-app`](apps/custom-server-app) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Custom Node.js server (`"start": "node server.js"` in `package.json`). | **Pass (Stand-down)**: `webnextjs` warns and stands down; container boots via custom `node server.js` and serves `/`, `/about`, `/dashboard`. |
| [`apps/monorepo-npm-turbo`](apps/monorepo-npm-turbo) | `npm` workspaces + Turborepo | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true`, `GOOGLE_BUILDABLE=apps/web` | Turborepo monorepo (`apps/web` + `packages/ui`) with `NEXT_PRIVATE_OUTPUT_TRACE_ROOT=/workspace`. | **Pass**: `webturborepo` filters build to `web`; standalone traces `@repo/ui`; `/` renders workspace package and `/dashboard` is guarded. |
| [`apps/monorepo-pnpm-turbo`](apps/monorepo-pnpm-turbo) | `pnpm` workspaces + Turborepo | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true`, `GOOGLE_BUILDABLE=apps/web` | pnpm + Turborepo monorepo (`apps/web` + `packages/ui`); verifies `.pnpm` virtual-store symlink preservation after pruning. | **Pass**: All `.pnpm` symlinks resolve in pruned standalone tree; `/` renders `@repo/ui` and `/dashboard` is guarded. |
| [`apps/monorepo-nx`](apps/monorepo-nx) | `npm` workspaces + Nx | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true`, `GOOGLE_BUILDABLE=apps/web` | Nx monorepo (`nx.json`, `apps/web` + `packages/ui`). | **Pass**: `webnx` runs `nx run web:build`; standalone traces `@repo/ui`; `/` renders workspace package and `/dashboard` is guarded. |
| [`apps/basepath-i18n`](apps/basepath-i18n) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | `basePath: '/base'` + Pages Router `i18n` (`locales: ['en', 'fr', 'de']`, `defaultLocale: 'en'`) + `proxy.ts` gating an SSG page (`/dashboard`). | **Pass**: Proxied paths under `/base` and every locale prefix (`/base/dashboard`, `/base/{en,fr,de}/dashboard`, `/base/_next/data/<buildId>/{en,fr,de}/dashboard.json`) are guarded (`private, no-cache, no-store, max-age=0, must-revalidate`, CDN headers stripped); unguarded SSG pages (`/base`, `/base/fr`, `/base/about`, `/base/de/about`) keep `s-maxage=31536000, max-age=0`. |
| [`apps/proxy-matchers`](apps/proxy-matchers) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | `proxy.ts` `config.matcher` entries with `has`/`missing` conditions (`header`, `cookie`, `query`) in front of SSG/ISR pages. | **Pass**: Adapter strips `has`/`missing` from `next-routing.json` (fail-closed), so matched paths (`/header-gated`, `/cookie-gated`, `/query-gated`) are guarded (`private, no-cache, no-store, max-age=0, must-revalidate`, all 4 CDN headers stripped) whether or not the condition holds; unmatched routes (`/`, `/public-isr`) keep `s-maxage` + `max-age=0`. |
| [`apps/config-conditional-routes`](apps/config-conditional-routes) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | No `proxy.ts`; `next.config.mjs` `rewrites()` and `headers()` with `has`/`missing` (`header` `x-tier`, `cookie` `tier=vip`) routing `/pricing` and `/offer` to different static pages. | **Known Gap** (`"mode": "known-gap"`): Runtime cache guard only covers `proxy.ts`/`middleware.ts` matchers, so conditional `next.config.mjs` rewrites/headers on static paths (`/pricing`, `/offer`) retain `s-maxage=31536000, max-age=0`. |
| [`apps/pages-router-proxy`](apps/pages-router-proxy) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true` | Pages Router SSG (`/guarded-ssg`), ISR (`/guarded-isr`), and API (`/api/guarded-api`) routes behind `proxy.ts`, plus `/_next/data/<buildId>/...json` requests. | **Pass**: Guarded Pages Router HTML pages, their `/_next/data/<buildId>/{guarded-ssg,guarded-isr}.json` data endpoints, and `/api/guarded-api` are clamped to `private, no-cache, no-store, max-age=0, must-revalidate` with `CDN-Cache-Control` stripped; unguarded SSG/ISR/API routes (`/`, `/_next/data/<buildId>/index.json`, `/public-isr`, `/api/public-api`) keep `s-maxage` + `max-age=0`. |
| [`apps/crashlytics-sourcemaps`](apps/crashlytics-sourcemaps) | `npm` | `GOOGLE_WEB_FRAMEWORKS=true`, `GOOGLE_WEB_PRUNE=true`, `CRASHLYTICS_UPLOAD_MAPPING=true` | Browser source map generation (`CRASHLYTICS_UPLOAD_MAPPING=true`) and `google.nodejs.websourcemaps` stripping + env var documentation (`GOOGLE_CRASHLYTICS_APP_ID`, `FIREBASE_CRASHLYTICS_APP_ID`, `FIREBASE_WEBAPP_CONFIG`, `GOOGLE_CLOUD_PROJECT`, `CRASHLYTICS_APP_VERSION`, `GOOGLE_CRASHLYTICS_APP_VERSION`, `K_REVISION`). | **Pass (with Manual)**: Adapter sets `productionBrowserSourceMaps: true` (emits `.js.map` files during `next build`) and `websourcemaps` strips all `.js.map` files from the final container image (`0` `.js.map` files in `/workspace`); live Crashlytics upload requires a real Firebase Web App ID + credentials and is marked `"mode": "manual"`. |

---

## Known Gaps & Limitations

1. **`next.config` conditional `rewrites` / `headers` (`has` / `missing`) without `proxy.ts`**:
   - Today's `.cloudrun/serve.js` cache guard evaluates `routing.middlewareMatchers` (from `proxy.ts` or `middleware.ts`), `beforeMiddleware` redirects, and malformed URL fail-closed checks. It does **not** clamp `Cache-Control` for routes that use `has` or `missing` conditions (such as cookie- or header-based rewrites) strictly inside `next.config` when no `proxy.ts` / `middleware.ts` matcher covers the path. See [`apps/config-conditional-routes`](apps/config-conditional-routes) for a reproducible test case.
2. **Cloud Run Platform CDN**:
   - Cloud Run's built-in platform CDN is not yet generally available on default `.run.app` endpoints. To test edge caching and `s-maxage` / `private` behavior end-to-end today, place **Cloud CDN** in front of your Cloud Run service using a Global External Application Load Balancer and a Serverless NEG with `--cache-mode=USE_ORIGIN_HEADERS`. See **[`docs/caching-with-cloud-cdn.md`](docs/caching-with-cloud-cdn.md)** for step-by-step instructions.
