# Testing Next.js Cache Behavior on Cloud Run with Cloud CDN

Cloud Run does not currently attach a managed platform CDN by default to `.run.app` service URLs. However, when you place **Cloud CDN** (via a Global External Application Load Balancer and a Serverless Network Endpoint Group) in front of a Cloud Run Next.js service, or when you connect a custom domain / upstream CDN that honors origin caching headers, Next.js's default `Cache-Control: s-maxage=31536000` on pre-rendered pages can cause responses behind `proxy.ts` / `middleware.ts` to be cached at the shared CDN edge unless guarded.

The `@google-cloud/adapter-nextjs` runtime wrapper (`.cloudrun/serve.js`) enforces a **fail-closed CDN cache guard**:

1. **Guarded routes (`proxy.ts` or `middleware.ts` matched)**:
   - Overwrites `Cache-Control` to `private, no-cache, no-store, max-age=0, must-revalidate`.
   - Strips CDN-specific override headers (`CDN-Cache-Control`, `Cloudflare-CDN-Cache-Control`, `Vercel-CDN-Cache-Control`, `Surrogate-Control`) so shared CDNs never cache personalized or gated responses.
2. **Unguarded static / ISR routes (`s-maxage` present)**:
   - Appends `max-age=0` alongside `s-maxage=<N>` (for example, `s-maxage=31536000, max-age=0` or `s-maxage=60, stale-while-revalidate=31535940, max-age=0`) so shared CDNs cache the response for `s-maxage` seconds while browsers always revalidate with the CDN edge.

This guide walks through setting up a **Global External Application Load Balancer + Serverless NEG + Cloud CDN (`USE_ORIGIN_HEADERS`)** in front of a deployed Cloud Run sample service to verify edge caching behavior end to end.

---

## Prerequisites

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export SERVICE_NAME="nextjs-single-app"

gcloud config set project "$PROJECT_ID"
```

First, pack the adapter and deploy `apps/single-app` to Cloud Run:

```bash
./scripts/pack-adapter.sh apps/single-app
./scripts/deploy.sh "$SERVICE_NAME" apps/single-app "$REGION" --prune=true
```

---

## Step 1: Create a Serverless NEG for the Cloud Run Service

Create a Serverless Network Endpoint Group (NEG) pointing to your Cloud Run service:

```bash
gcloud compute network-endpoint-groups create "${SERVICE_NAME}-neg" \
  --region="$REGION" \
  --network-endpoint-type=serverless \
  --cloud-run-service="$SERVICE_NAME"
```

---

## Step 2: Create a Backend Service with Cloud CDN (`USE_ORIGIN_HEADERS`)

Create a global backend service configured with `--enable-cdn` and `--cache-mode=USE_ORIGIN_HEADERS` so Cloud CDN strictly respects the `Cache-Control` headers emitted by `.cloudrun/serve.js` (rather than `CACHE_ALL_STATIC` heuristics):

```bash
gcloud compute backend-services create "${SERVICE_NAME}-backend" \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTP \
  --enable-cdn \
  --cache-mode=USE_ORIGIN_HEADERS \
  --global

gcloud compute backend-services add-backend "${SERVICE_NAME}-backend" \
  --network-endpoint-group="${SERVICE_NAME}-neg" \
  --network-endpoint-group-region="$REGION" \
  --global
```

> **Why `USE_ORIGIN_HEADERS`?**
> By default, Cloud CDN uses `CACHE_ALL_STATIC`, which only caches responses based on MIME type or when `public` is present in `Cache-Control`. Next.js emits `Cache-Control: s-maxage=31536000` (without `public`) for static and ISR HTML/RSC payloads. Setting `--cache-mode=USE_ORIGIN_HEADERS` instructs Cloud CDN to cache any response carrying `s-maxage` or `public` while never caching responses marked `private`, `no-store`, or `no-cache`.

---

## Step 3: Create the URL Map, HTTP(S) Target Proxy, and Forwarding Rule

For a quick HTTP test endpoint (or attach a managed SSL certificate and `target-https-proxies` for HTTPS):

```bash
# Reserve a global static IPv4 address
gcloud compute addresses create "${SERVICE_NAME}-ip" \
  --ip-version=IPV4 \
  --global

export LB_IP="$(gcloud compute addresses describe "${SERVICE_NAME}-ip" --global --format='get(address)')"
echo "Load Balancer IP: $LB_IP"

# Create URL map
gcloud compute url-maps create "${SERVICE_NAME}-urlmap" \
  --default-service="${SERVICE_NAME}-backend" \
  --global

# Create HTTP target proxy
gcloud compute target-http-proxies create "${SERVICE_NAME}-http-proxy" \
  --url-map="${SERVICE_NAME}-urlmap" \
  --global

# Create global forwarding rule on port 80
gcloud compute forwarding-rules create "${SERVICE_NAME}-http-rule" \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --network-tier=PREMIUM \
  --address="${SERVICE_NAME}-ip" \
  --target-http-proxy="${SERVICE_NAME}-http-proxy" \
  --ports=80 \
  --global
```

*(Note: New global forwarding rules typically take 3–5 minutes to propagate to Google Front Ends.)*

---

## Step 4: Verify Edge Cache Hits vs. Guarded Bypasses

Once the Load Balancer IP is active, run `scripts/verify.mjs` against `http://$LB_IP`:

```bash
node ./scripts/verify.mjs apps/single-app "http://$LB_IP"
```

You can also inspect Cloud CDN's `Age` header across repeated requests:

### 1. Unguarded Static Route (`/about`) — Cached at Edge (`Age` > 0)

```bash
# Request 1 (populates Cloud CDN cache)
curl -i "http://$LB_IP/about"

# Request 2 (served from Cloud CDN edge)
curl -i "http://$LB_IP/about"
```

Expected headers on the second request:

```http
HTTP/1.1 200 OK
cache-control: s-maxage=31536000, max-age=0
age: 4
x-about-header: 1
```

- Cloud CDN caches the response using `s-maxage=31536000` (`age` increments on subsequent requests).
- Browsers see `max-age=0` and revalidate with the CDN on navigation.

### 2. Unguarded ISR Route (`/blog/a`) — Cached for 60s (`s-maxage=60`)

```bash
curl -i "http://$LB_IP/blog/a"
curl -i "http://$LB_IP/blog/a"
```

Expected headers:

```http
HTTP/1.1 200 OK
cache-control: s-maxage=60, stale-while-revalidate=31535940, max-age=0
age: 2
```

### 3. Guarded Proxy Route (`/dashboard`) — Never Cached (`private, no-store`)

```bash
curl -i "http://$LB_IP/dashboard"
curl -i "http://$LB_IP/dashboard"
```

Expected headers on every request:

```http
HTTP/1.1 200 OK
cache-control: private, no-cache, no-store, max-age=0, must-revalidate
x-proxy-ran: 1
```

- No `age` header is present; every request reaches the Cloud Run instance and executes `proxy.ts`.

---

## Cleanup

To remove the Load Balancer, Backend Service, and Serverless NEG:

```bash
gcloud compute forwarding-rules delete "${SERVICE_NAME}-http-rule" --global --quiet
gcloud compute target-http-proxies delete "${SERVICE_NAME}-http-proxy" --global --quiet
gcloud compute url-maps delete "${SERVICE_NAME}-urlmap" --global --quiet
gcloud compute backend-services delete "${SERVICE_NAME}-backend" --global --quiet
gcloud compute network-endpoint-groups delete "${SERVICE_NAME}-neg" --region="$REGION" --quiet
gcloud compute addresses delete "${SERVICE_NAME}-ip" --global --quiet
```
