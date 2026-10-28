# `crashlytics-sourcemaps`

Minimal Next.js 16.4 sample testing **browser source map generation and stripping** via `@google-cloud/adapter-nextjs` and the `google.nodejs.websourcemaps` buildpack (`CRASHLYTICS_UPLOAD_MAPPING=true`).

## What This Sample Covers

1. **Build-time browser source map generation (`@google-cloud/adapter-nextjs`)**:
   - When `CRASHLYTICS_UPLOAD_MAPPING=true` (or `"1"`), `modifyConfig` in `@google-cloud/adapter-nextjs` sets `productionBrowserSourceMaps: true` in `next.config` so `next build` emits `.js.map` files alongside client chunks in `.next/static/chunks/`.
   - When `GOOGLE_CRASHLYTICS_APP_ID` or `FIREBASE_CRASHLYTICS_APP_ID` is set and `CRASHLYTICS_UPLOAD_MAPPING` is not explicitly set, `google.nodejs.webnextjs` defaults `CRASHLYTICS_UPLOAD_MAPPING=true` automatically.
2. **Crashlytics upload & mandatory `.js.map` stripping (`google.nodejs.websourcemaps`)**:
   - Opts in when `GOOGLE_WEB_FRAMEWORKS=true` (on the `ALPHA` track) and `CRASHLYTICS_UPLOAD_MAPPING` is `"true"`/`"1"`, or when `GOOGLE_CRASHLYTICS_APP_ID` or `FIREBASE_CRASHLYTICS_APP_ID` is set (unless `CRASHLYTICS_UPLOAD_MAPPING` is explicitly `"false"` or `"0"`).
   - Resolves the target `.next` directory from `.cloudrun/bundle.yaml` (`metadata.serverDir` / `metadata.distDir` / `.cloudrun/standalone/.next`).
   - If a Crashlytics App ID is configured, installs `firebase-tools@15.33.0` into a cached build-only layer (`firebase_tools`) and executes:
     ```bash
     FIREBASE_CLI_EXPERIMENTS=crashlyticsWeb \
       firebase crashlytics:sourcemap:upload <shippedNextDir> \
       --app <appId> --app-version <appVersion> [--project <projectId>]
     ```
   - If no App ID is provided or if the upload fails, logs a non-fatal warning (`WARNING: [websourcemaps] ...`) and continues the build.
   - **Always strips all `.js.map` files** under `/workspace` (outside `node_modules`) before image export (`defer stripAllSourceMaps(ctx)`), ensuring source maps are never publicly served in the container image.

## Crashlytics & Firebase Environment Variables Read by `google.nodejs.websourcemaps`

| Variable | Phase | Role in `google.nodejs.websourcemaps` / `webnextjs` |
| :--- | :--- | :--- |
| `CRASHLYTICS_UPLOAD_MAPPING` | Detect & Build | Enables source map generation (`true` or `1`) in `@google-cloud/adapter-nextjs` and opts `websourcemaps` into the build. Setting `false` or `0` explicitly opts out even if an App ID variable is present. |
| `GOOGLE_CRASHLYTICS_APP_ID` | Detect & Build | Primary Crashlytics Web App ID (e.g., `1:1234567890:web:abcdef123456`). Also triggers `websourcemaps` detection and defaults `CRASHLYTICS_UPLOAD_MAPPING=true` in `webnextjs` when `CRASHLYTICS_UPLOAD_MAPPING` is unset. |
| `FIREBASE_CRASHLYTICS_APP_ID` | Detect & Build | Fallback Crashlytics Web App ID if `GOOGLE_CRASHLYTICS_APP_ID` is unset. Also triggers `websourcemaps` detection and defaults `CRASHLYTICS_UPLOAD_MAPPING=true` in `webnextjs`. |
| `FIREBASE_WEBAPP_CONFIG` | Build | Optional JSON string (`{"appId":"...","projectId":"..."}`). Used as a fallback source for `appId` (if neither `GOOGLE_CRASHLYTICS_APP_ID` nor `FIREBASE_CRASHLYTICS_APP_ID` is set) and `projectId` (if `GOOGLE_CLOUD_PROJECT` is unset). Note: `FIREBASE_WEBAPP_CONFIG` alone does not trigger `DetectFn`; set `CRASHLYTICS_UPLOAD_MAPPING=true` alongside it. |
| `GOOGLE_CLOUD_PROJECT` | Build | GCP / Firebase project ID passed as `--project <projectId>` to `firebase crashlytics:sourcemap:upload` (falls back to `FIREBASE_WEBAPP_CONFIG.projectId`). |
| `CRASHLYTICS_APP_VERSION` | Build | Highest-priority override for `--app-version <version>` passed to `firebase crashlytics:sourcemap:upload`. |
| `GOOGLE_CRASHLYTICS_APP_VERSION` | Build | Second-priority override for `--app-version <version>` if `CRASHLYTICS_APP_VERSION` is unset. |
| `K_REVISION` | Build | Third-priority fallback for `--app-version <version>` before falling back to `"version"` in `package.json` and finally `"0.0.0"`. |

## Expected Results

- **During `next build` (with `CRASHLYTICS_UPLOAD_MAPPING=true` and `NEXT_ADAPTER_PATH`)**:
  - `.next/static/chunks/*.js.map` files are produced.
- **After `pack build` (`google.nodejs.websourcemaps` + `google.nodejs.webbundle`)**:
  - `0` `.js.map` files remain anywhere under `/workspace` in the final container image.
  - `GET /` returns `200 OK` with `Cache-Control: s-maxage=31536000, max-age=0`.
  - `GET /dashboard` returns `200 OK` with `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` and `x-proxy-ran: 1`.
- **Manual Check**:
  - Actual source map upload to Firebase Crashlytics requires a real Firebase project and Web App ID (`GOOGLE_CRASHLYTICS_APP_ID` + `GOOGLE_CLOUD_PROJECT`) with active credentials, and is marked `"mode": "manual"` in `expectations.json`.
