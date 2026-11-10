# `crashlytics-sourcemaps`

Minimal Next.js 16.4 sample built with `CRASHLYTICS_UPLOAD_MAPPING=true`. It checks that the app's browser source maps are **not** published while Crashlytics source-map upload isn't available on Cloud Run.

## What This Sample Covers

1. **`@google-cloud/adapter-nextjs` ignores `CRASHLYTICS_UPLOAD_MAPPING` for now**:
   - `modifyConfig` doesn't turn on `productionBrowserSourceMaps`, so `next build` emits no `.js.map` files for client chunks under `.next/static`.
   - It logs one warning instead:
     ```text
     [adapter-nextjs] Warning: Ignoring CRASHLYTICS_UPLOAD_MAPPING=true: Crashlytics source-map upload isn't available on Cloud Run yet, and enabling browser source maps would serve the app's source publicly. NextConfig productionBrowserSourceMaps is left unchanged.
     ```
   - Why: with browser source maps on and nothing to upload and strip them, every client chunk's map is served from `/_next/static/chunks/` with `Cache-Control: public, max-age=31536000, immutable`, including the full `sourcesContent`.
   - The app's own `productionBrowserSourceMaps` setting in `next.config` is never changed. This sample doesn't set one.
2. **Crashlytics source-map upload is a known gap**: uploading the maps to Crashlytics during the build (and then removing them from the image) isn't available yet. Until it ships, `expectations.json` marks the upload check `known-gap`.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` \| `report-only` \| `false` | Every mode verifies from the same `expectations.json` (the serve-mode label follows the mode). |
| `CRASHLYTICS_UPLOAD_MAPPING` | `true` (from `buildEnv` in `expectations.json`) | Ignored by the adapter for now; see above. |

## Expected Results

- **Build log**: the `[adapter-nextjs] Warning: Ignoring CRASHLYTICS_UPLOAD_MAPPING=true` line, and no `Enabling NextConfig productionBrowserSourceMaps=true` line. `verify.mjs` checks this when it has the build log (`--build-log=<file>`, or the log `local-pack.sh` saves); otherwise the check is reported as `manual`.
- **Image**: `0` `.js.map` files under any `.next/static` directory in `/workspace` (`node_modules` is skipped). Server-side `.js.map` files under `.next/server` aren't served and aren't counted.
- **Runtime**:
  - `GET /` returns `200 OK` with `Cache-Control: s-maxage=31536000, max-age=0`.
  - `GET /dashboard` returns `200 OK` with `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` and `x-proxy-ran: 1`.
  - For every `/_next/static/chunks/*.js` that `/` and `/dashboard` load, the chunk returns `200`, and its source map is not served: neither the map named by the chunk's `//# sourceMappingURL=` comment (Turbopack names maps by their own hash, not `<chunk>.js.map`) nor `<chunk>.js.map`.
- **Known gap**: the actual upload to Firebase Crashlytics, which will need a Firebase Web App ID and project credentials.
