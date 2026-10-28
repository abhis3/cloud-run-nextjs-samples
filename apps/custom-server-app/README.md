# `custom-server-app` — Custom Node.js Server (`"start": "node server.js"`) Stand-Down

## Overview

`custom-server-app` includes a custom Node.js HTTP server (`server.js`) and sets `"start": "node server.js"` in `package.json`.

When `google.nodejs.webnextjs` runs, it inspects the application's start configuration (`nodejs.WebStandDownReason`), detects the custom start script `"node server.js"`, logs:

```text
WARNING: [webnextjs] Standing down: custom start script "node server.js" in package.json; continuing with generic Node.js build.
```

and stands down without injecting `@google-cloud/adapter-nextjs` or overriding the start command. The container boots via `npm start` (`node server.js`) as a standard Cloud Run Node.js service.

## Build Environment Variables

| Variable | Value | Description |
| :--- | :--- | :--- |
| `GOOGLE_WEB_FRAMEWORKS` | `true` | Enables framework-aware Next.js buildpacks (which detect the custom server and stand down). |
| `GOOGLE_NEXTJS_ADAPTER_VERSION` | `file:./google-cloud-adapter-nextjs-0.1.0.tgz` | Local packed `@google-cloud/adapter-nextjs` tarball. |
| `GOOGLE_WEB_PRUNE` | `true` | Ignored because `webnextjs` stands down and no `.cloudrun/bundle.yaml` is emitted. |

## Expected Build & Runtime Results

- Image labels `google.web-cache-guard` and `google.web-serve-mode` are **not** set.
- Container boots with the user's custom `server.js` entrypoint.

| Route | Status | Expected Behavior |
| :--- | :--- | :--- |
| `GET /` | `200` | Renders `Home Page` via `server.js`. |
| `GET /about` | `200` | Renders `About Page` via `server.js`. |
| `GET /dashboard` | `200` | Renders `Dashboard Secret Area` with `x-proxy-ran: 1` (without `.cloudrun/serve.js` cache guard). |
