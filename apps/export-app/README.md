# `export-app` — Static Export (`output: 'export'`) Stand-Down

## Overview

`export-app` configures `output: 'export'` in `next.config.mjs`. It verifies the safe fallback behavior of both the adapter and the `google.nodejs.webbundle` buildpack:

1. `@google-cloud/adapter-nextjs` detects `output: 'export'`, logs `[adapter-nextjs] NextConfig has output: "export"; preserving static export mode.`, does **not** overwrite `output` with `'standalone'`, and writes `.cloudrun/bundle.yaml` with `outputMode: export`.
2. `google.nodejs.webbundle` reads `.cloudrun/bundle.yaml`, logs `WARNING: [webbundle] Static export detected (outputMode: export in .cloudrun/bundle.yaml). Cloud Run requires a server process; skipping standalone bundle and leaving default start command unchanged.`, and exits `0` without pruning or overriding the entrypoint.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks. |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Requested prune mode (safely skipped by `webbundle` due to `outputMode: export`). |

## Expected Build & Verification Results

- Build succeeds (`exit 0`) and emits the `[webbundle] Static export detected` warning.
- Static HTML files are generated in `/workspace/out/`.
- Image labels `google.web-cache-guard` and `google.web-serve-mode` are **not** set.
- `expectations.json` sets `"skipRuntime": true` because `output: 'export'` does not produce a Next.js server process.
