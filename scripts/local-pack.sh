#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
#
# Builds a Next.js sample app into a container image locally using `pack build`
# with a locally created GCP buildpacks builder image, X_GOOGLE_RELEASE_TRACK=ALPHA,
# GOOGLE_WEB_FRAMEWORKS=true, and the packed @google-cloud/adapter-nextjs .tgz.
#
# Usage:
#   ./scripts/local-pack.sh <app-dir-or-name> [<image-tag>] [--prune=true|report-only|false] [--env KEY=VAL ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/local-pack.sh <app-dir-or-name> [<image-tag>] [options]

Options:
  --app=<app-dir-or-name>    Sample app directory (e.g. apps/single-app or single-app).
  --image=<image-tag>        Output Docker image tag (default: fab-sample-<app>:latest).
  --builder=<builder-image>  Builder image (default: gcr.io/buildpacks/builder:latest).
  --prune=<mode>             GOOGLE_WEB_PRUNE value: true, report-only, or false (default: true).
  --no-prune                 Omit GOOGLE_WEB_PRUNE (uses buildpack default: report-only).
  --adapter-version=<spec>   Override GOOGLE_NEXTJS_ADAPTER_VERSION (default: file:./<packed>.tgz).
  --env=<KEY=VAL>, -e        Additional build environment variable (repeatable).
  --clear-cache              Pass --clear-cache to pack build.
  -h, --help                 Show this help message.
EOF
}

APP_INPUT=""
IMAGE_TAG=""
BUILDER="${FAB_BUILDER:-}"
PRUNE_MODE="${GOOGLE_WEB_PRUNE:-true}"
INCLUDE_PRUNE=true
ADAPTER_VERSION_OVERRIDE="${GOOGLE_NEXTJS_ADAPTER_VERSION:-}"
CLEAR_CACHE=false
EXTRA_ENVS=()
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app=*|--source=*|--path=*)
      APP_INPUT="${1#*=}"
      shift
      ;;
    --app|--source|--path)
      APP_INPUT="$2"
      shift 2
      ;;
    --image=*|--tag=*)
      IMAGE_TAG="${1#*=}"
      shift
      ;;
    --image|--tag|-t)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --builder=*)
      BUILDER="${1#--builder=}"
      shift
      ;;
    --builder|-B)
      BUILDER="$2"
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
      EXTRA_ENVS+=("${1#--env=}")
      shift
      ;;
    --env|-e)
      EXTRA_ENVS+=("$2")
      shift 2
      ;;
    --clear-cache)
      CLEAR_CACHE=true
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

if [[ -z "$APP_INPUT" && "${#POSITIONAL[@]}" -ge 1 ]]; then
  APP_INPUT="${POSITIONAL[0]}"
fi
if [[ -z "$IMAGE_TAG" && "${#POSITIONAL[@]}" -ge 2 ]]; then
  IMAGE_TAG="${POSITIONAL[1]}"
fi

if [[ -z "$APP_INPUT" ]]; then
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

APP_NAME="$(basename "$APP_DIR")"
if [[ -z "$IMAGE_TAG" ]]; then
  IMAGE_TAG="fab-sample-${APP_NAME}:latest"
fi

# Resolve builder image (defaults to the public builder gcr.io/buildpacks/builder:latest).
if [[ -z "$BUILDER" ]]; then
  BUILDER="gcr.io/buildpacks/builder:latest"
fi

# Ensure an anonymous DOCKER_CONFIG is used if none was set, avoiding credential
# helper failures against public stack images.
TEMP_DOCKER_CFG=""
if [[ -z "${DOCKER_CONFIG:-}" ]]; then
  TEMP_DOCKER_CFG="$(mktemp -d "${TMPDIR:-/tmp}/docker-anon-cfg.XXXXXX")"
  printf '{"auths":{}}\n' > "$TEMP_DOCKER_CFG/config.json"
  export DOCKER_CONFIG="$TEMP_DOCKER_CFG"
fi

# Ensure the adapter tarball exists in APP_DIR unless overridden.
if [[ -z "$ADAPTER_VERSION_OVERRIDE" ]]; then
  EXISTING_TGZ="$(ls -1 "$APP_DIR"/google-cloud-adapter-nextjs-*.tgz 2>/dev/null | head -n 1 || true)"
  if [[ -z "$EXISTING_TGZ" ]]; then
    if [[ -f "$REPO_ROOT/.cache/google-cloud-adapter-nextjs-0.1.0.tgz" ]]; then
      cp -f "$REPO_ROOT/.cache/google-cloud-adapter-nextjs-0.1.0.tgz" "$APP_DIR/"
      EXISTING_TGZ="$APP_DIR/google-cloud-adapter-nextjs-0.1.0.tgz"
    else
      "$SCRIPT_DIR/pack-adapter.sh" "$APP_DIR"
      EXISTING_TGZ="$(ls -1 "$APP_DIR"/google-cloud-adapter-nextjs-*.tgz 2>/dev/null | head -n 1 || true)"
    fi
  fi
  ADAPTER_SPEC="file:./$(basename "$EXISTING_TGZ")"
else
  ADAPTER_SPEC="$ADAPTER_VERSION_OVERRIDE"
fi

# Stage the app into a clean temporary directory (excluding local host
# node_modules or build artifacts) so `pack build` always starts from clean source.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fab-pack-stage-${APP_NAME}.XXXXXX")"
cleanup() {
  rm -rf "$STAGE_DIR"
  if [[ -n "$TEMP_DOCKER_CFG" ]]; then
    rm -rf "$TEMP_DOCKER_CFG"
  fi
}
trap cleanup EXIT

tar -C "$APP_DIR" \
  --exclude='./node_modules' \
  --exclude='./**/node_modules' \
  --exclude='./.next' \
  --exclude='./**/.next' \
  --exclude='./out' \
  --exclude='./.turbo' \
  --exclude='./.nx' \
  --exclude='./.cloudrun' \
  --exclude='./dumps' \
  -cf - . | tar -C "$STAGE_DIR" -xf -

PACK_ENV_ARGS=(
  --env "X_GOOGLE_RELEASE_TRACK=ALPHA"
  --env "GOOGLE_WEB_FRAMEWORKS=true"
  --env "GOOGLE_NEXTJS_ADAPTER_VERSION=${ADAPTER_SPEC}"
)

if [[ "$INCLUDE_PRUNE" == "true" && -n "$PRUNE_MODE" ]]; then
  PACK_ENV_ARGS+=(--env "GOOGLE_WEB_PRUNE=${PRUNE_MODE}")
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
    for existing in "${EXTRA_ENVS[@]}"; do
      if [[ "${existing%%=*}" == "$KEY" ]]; then
        ALREADY_SET=true
        break
      fi
    done
    if [[ "$ALREADY_SET" == "false" ]]; then
      PACK_ENV_ARGS+=(--env "$kv")
    fi
  done < <(read_build_env "$APP_DIR/expectations.json")
fi

for kv in "${EXTRA_ENVS[@]}"; do
  PACK_ENV_ARGS+=(--env "$kv")
done

PACK_ARGS=(
  build "$IMAGE_TAG"
  --builder "$BUILDER"
  --path "$STAGE_DIR"
  --pull-policy if-not-present
  --network host
  --trust-builder
  "${PACK_ENV_ARGS[@]}"
)

if [[ "$CLEAR_CACHE" == "true" ]]; then
  PACK_ARGS+=(--clear-cache)
fi

echo "Building $APP_NAME -> $IMAGE_TAG with builder $BUILDER..."
pack "${PACK_ARGS[@]}"

# Also tag as <app-name>:latest and fab-sample-<app-name>:latest for convenience.
if [[ "$IMAGE_TAG" != "${APP_NAME}:latest" ]]; then
  docker tag "$IMAGE_TAG" "${APP_NAME}:latest" 2>/dev/null || true
fi
if [[ "$IMAGE_TAG" != "fab-sample-${APP_NAME}:latest" ]]; then
  docker tag "$IMAGE_TAG" "fab-sample-${APP_NAME}:latest" 2>/dev/null || true
fi

echo "Built image: $IMAGE_TAG"
