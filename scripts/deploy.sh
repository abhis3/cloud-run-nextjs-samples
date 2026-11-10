#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
#
# Deploys a Next.js sample app from source to Cloud Run using the alpha-track
# framework-aware buildpacks and @google-cloud/adapter-nextjs.
#
# Usage:
#   ./scripts/deploy.sh <service-name> <app-dir> [<region>] [--prune=true|report-only|false] [--env KEY=VAL ...]
#   ./scripts/deploy.sh --service=<svc> --source=<app-dir> [--region=<region>] [--prune=true|report-only|false]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy.sh <service-name> <app-dir> [<region>] [options]
  ./scripts/deploy.sh --service=<service-name> --source=<app-dir> [--region=<region>] [options]

Options:
  --service=<name>           Cloud Run service name.
  --source=<app-dir>         Path to the sample app directory (e.g. apps/single-app).
  --region=<region>          Cloud Run region (default: $REGION or us-central1).
  --project=<project-id>     Google Cloud project ID (optional; defaults to gcloud config).
  --prune=<mode>             GOOGLE_WEB_PRUNE value: true, report-only, or false (default: true).
  --no-prune                 Omit GOOGLE_WEB_PRUNE (uses buildpack default: report-only).
  --adapter-version=<spec>   Override GOOGLE_NEXTJS_ADAPTER_VERSION (default: file:./<packed>.tgz).
  --env=<KEY=VAL>            Additional build environment variable (repeatable).
  --allow-unauthenticated    Pass --allow-unauthenticated to gcloud alpha run deploy (default).
  --no-allow-unauthenticated Pass --no-allow-unauthenticated to gcloud alpha run deploy.
  --dry-run                  Print the gcloud command without executing it.
  -h, --help                 Show this help message.
EOF
}

SERVICE_NAME=""
APP_INPUT=""
REGION="${REGION:-us-central1}"
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
PRUNE_MODE="${GOOGLE_WEB_PRUNE:-true}"
INCLUDE_PRUNE=true
ADAPTER_VERSION_OVERRIDE="${GOOGLE_NEXTJS_ADAPTER_VERSION:-}"
AUTH_FLAG="--allow-unauthenticated"
DRY_RUN=false
EXTRA_BUILD_ENVS=()
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service=*)
      SERVICE_NAME="${1#--service=}"
      shift
      ;;
    --service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --source=*|--app=*)
      APP_INPUT="${1#*=}"
      shift
      ;;
    --source|--app)
      APP_INPUT="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#--region=}"
      shift
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --project=*)
      PROJECT_ID="${1#--project=}"
      shift
      ;;
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --prune=*)
      PRUNE_MODE="${1#--prune=}"
      INCLUDE_PRUNE=true
      shift
      ;;
    --no-prune)
      INCLUDE_PRUNE=false
      shift
      ;;
    --adapter-version=*)
      ADAPTER_VERSION_OVERRIDE="${1#--adapter-version=}"
      shift
      ;;
    --env=*)
      EXTRA_BUILD_ENVS+=("${1#--env=}")
      shift
      ;;
    --env|-e)
      EXTRA_BUILD_ENVS+=("$2")
      shift 2
      ;;
    --allow-unauthenticated)
      AUTH_FLAG="--allow-unauthenticated"
      shift
      ;;
    --no-allow-unauthenticated)
      AUTH_FLAG="--no-allow-unauthenticated"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$SERVICE_NAME" && "${#POSITIONAL[@]}" -ge 1 ]]; then
  SERVICE_NAME="${POSITIONAL[0]}"
fi
if [[ -z "$APP_INPUT" && "${#POSITIONAL[@]}" -ge 2 ]]; then
  APP_INPUT="${POSITIONAL[1]}"
fi
if [[ "${#POSITIONAL[@]}" -ge 3 ]]; then
  REGION="${POSITIONAL[2]}"
fi

if [[ -z "$SERVICE_NAME" || -z "$APP_INPUT" ]]; then
  usage >&2
  exit 1
fi

if [[ -d "$APP_INPUT" ]]; then
  APP_DIR="$(cd "$APP_INPUT" && pwd)"
elif [[ -d "$REPO_ROOT/$APP_INPUT" ]]; then
  APP_DIR="$(cd "$REPO_ROOT/$APP_INPUT" && pwd)"
elif [[ -d "$REPO_ROOT/apps/$APP_INPUT" ]]; then
  APP_DIR="$(cd "$REPO_ROOT/apps/$APP_INPUT" && pwd)"
else
  echo "ERROR: App directory not found: $APP_INPUT" >&2
  exit 1
fi

# Determine GOOGLE_NEXTJS_ADAPTER_VERSION.
# The google.nodejs.webnextjs buildpack treats any value starting with "file:",
# "/", "./", "../", or ending in ".tgz"/".tar.gz" as a local tarball/file spec
# and passes it directly to:
#   npm install --prefix /layers/google.nodejs.webnextjs/web_nextjs_adapter <spec>
# executed with working directory /workspace (the uploaded --source root).
if [[ -n "$ADAPTER_VERSION_OVERRIDE" ]]; then
  ADAPTER_SPEC="$ADAPTER_VERSION_OVERRIDE"
else
  EXISTING_TGZ="$(ls -1 "$APP_DIR"/google-cloud-adapter-nextjs-*.tgz 2>/dev/null | head -n 1 || true)"
  if [[ -z "$EXISTING_TGZ" ]]; then
    echo "No adapter tarball found in $APP_DIR; packing via scripts/pack-adapter.sh..."
    "$SCRIPT_DIR/pack-adapter.sh" "$APP_DIR"
    EXISTING_TGZ="$(ls -1 "$APP_DIR"/google-cloud-adapter-nextjs-*.tgz 2>/dev/null | head -n 1 || true)"
  fi
  ADAPTER_SPEC="file:./$(basename "$EXISTING_TGZ")"
fi

BUILD_ENV_LIST=("GOOGLE_WEB_FRAMEWORKS=true" "GOOGLE_NEXTJS_ADAPTER_VERSION=${ADAPTER_SPEC}")
if [[ "$INCLUDE_PRUNE" == "true" && -n "$PRUNE_MODE" ]]; then
  BUILD_ENV_LIST+=("GOOGLE_WEB_PRUNE=${PRUNE_MODE}")
fi

# Read default buildEnv entries from expectations.json if present.
read_build_env() {
  local exp_file="$1"
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const exp = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      for (const [k, v] of Object.entries(exp.buildEnv || {})) {
        console.log(`${k}=${v}`);
      }
    ' "$exp_file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; exp=json.load(open(sys.argv[1])); [print(f"{k}={v}") for k,v in (exp.get("buildEnv") or {}).items()]' "$exp_file"
  fi
}

if [[ -f "$APP_DIR/expectations.json" ]]; then
  while IFS= read -r kv; do
    [[ -z "$kv" ]] && continue
    KEY="${kv%%=*}"
    ALREADY_SET=false
    for existing in "${BUILD_ENV_LIST[@]}" "${EXTRA_BUILD_ENVS[@]}"; do
      if [[ "${existing%%=*}" == "$KEY" ]]; then
        ALREADY_SET=true
        break
      fi
    done
    if [[ "$ALREADY_SET" == "false" ]]; then
      BUILD_ENV_LIST+=("$kv")
    fi
  done < <(read_build_env "$APP_DIR/expectations.json")
fi

for kv in "${EXTRA_BUILD_ENVS[@]}"; do
  BUILD_ENV_LIST+=("$kv")
done

IFS=',' BUILD_ENV_ARG="${BUILD_ENV_LIST[*]}"
unset IFS

CMD=(
  gcloud alpha run deploy "$SERVICE_NAME"
  --source "$APP_DIR"
  --region "$REGION"
  "$AUTH_FLAG"
  "--set-build-env-vars=${BUILD_ENV_ARG}"
)
if [[ -n "$PROJECT_ID" ]]; then
  CMD+=(--project "$PROJECT_ID")
fi

echo "Running: ${CMD[*]}"
if [[ "$DRY_RUN" == "true" ]]; then
  exit 0
fi

"${CMD[@]}"

# The GOOGLE_WEB_PRUNE mode this deploy built with: the last value set, or the buildpack default.
EFFECTIVE_PRUNE="report-only"
for kv in "${BUILD_ENV_LIST[@]}"; do
  if [[ "$kv" == GOOGLE_WEB_PRUNE=* ]]; then
    EFFECTIVE_PRUNE="${kv#GOOGLE_WEB_PRUNE=}"
  fi
done
echo "Verify the service (GOOGLE_WEB_PRUNE=$EFFECTIVE_PRUNE; image labels and files are only checked with --image):"
echo "  node $REPO_ROOT/scripts/verify.mjs $APP_DIR <service-url> --prune=$EFFECTIVE_PRUNE [--build-log=<saved Cloud Build log>]"
