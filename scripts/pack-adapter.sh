#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
#
# Builds and packs @google-cloud/adapter-nextjs from the apphosting-adapters
# repository (origin/main) in a temporary git worktree, then copies the
# resulting .tgz tarball into one or more sample app directories.
#
# Usage:
#   ./scripts/pack-adapter.sh <app-dir> [<app-dir> ...]
#   ./scripts/pack-adapter.sh --all
#
# Environment variables:
#   APPHOSTING_ADAPTERS_REPO  Path or URL to firebase/apphosting-adapters repo
#                             (defaults to sibling ../apphosting-adapters if
#                             present, otherwise clones from GitHub).
#   ADAPTER_GIT_REF           Git ref to build from (default: origin/main).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER_GIT_REF="${ADAPTER_GIT_REF:-origin/main}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/pack-adapter.sh <app-dir-or-name> [<app-dir-or-name> ...]
  ./scripts/pack-adapter.sh --all

Options:
  --all                 Copy the packed adapter .tgz into every apps/* directory.
  --ref=<git-ref>       Git ref in apphosting-adapters to pack (default: origin/main).
  --repo=<path>         Path to local apphosting-adapters checkout.
  -h, --help            Show this help message.
EOF
}

TARGETS=()
COPY_ALL=false

for arg in "$@"; do
  case "$arg" in
    --all)
      COPY_ALL=true
      ;;
    --ref=*)
      ADAPTER_GIT_REF="${arg#--ref=}"
      ;;
    --repo=*)
      APPHOSTING_ADAPTERS_REPO="${arg#--repo=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      TARGETS+=("$arg")
      ;;
  esac
done

if [[ "$COPY_ALL" == "false" && "${#TARGETS[@]}" -eq 0 ]]; then
  COPY_ALL=true
fi

resolve_target_dir() {
  local raw="$1"
  if [[ -d "$raw" ]]; then
    (cd "$raw" && pwd)
    return 0
  fi
  if [[ -d "$REPO_ROOT/$raw" ]]; then
    (cd "$REPO_ROOT/$raw" && pwd)
    return 0
  fi
  if [[ -d "$REPO_ROOT/apps/$raw" ]]; then
    (cd "$REPO_ROOT/apps/$raw" && pwd)
    return 0
  fi
  echo "ERROR: Target app directory not found: $raw" >&2
  return 1
}

RESOLVED_TARGETS=()
if [[ "$COPY_ALL" == "true" ]]; then
  for d in "$REPO_ROOT"/apps/*; do
    if [[ -d "$d" ]]; then
      RESOLVED_TARGETS+=("$d")
    fi
  done
else
  for t in "${TARGETS[@]}"; do
    RESOLVED_TARGETS+=("$(resolve_target_dir "$t")")
  done
fi

# Locate or clone firebase/apphosting-adapters.
CLONED_REPO_DIR=""
ADAPTER_REPO="${APPHOSTING_ADAPTERS_REPO:-}"

if [[ -z "$ADAPTER_REPO" ]]; then
  if [[ -d "$(dirname "$REPO_ROOT")/apphosting-adapters/.git" ]]; then
    ADAPTER_REPO="$(cd "$(dirname "$REPO_ROOT")/apphosting-adapters" && pwd)"
  elif git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    TOP="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)"
    if [[ -d "$TOP/packages/@google-cloud/adapter-nextjs" ]]; then
      ADAPTER_REPO="$TOP"
    fi
  fi
fi

WT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adapter-nextjs-wt.XXXXXX")"
cleanup() {
  if [[ -n "$ADAPTER_REPO" && -d "$ADAPTER_REPO/.git" ]]; then
    git -C "$ADAPTER_REPO" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$WT_DIR"
  if [[ -n "$CLONED_REPO_DIR" ]]; then
    rm -rf "$CLONED_REPO_DIR"
  fi
}
trap cleanup EXIT

if [[ -n "$ADAPTER_REPO" && -d "$ADAPTER_REPO/.git" ]]; then
  if ! git -C "$ADAPTER_REPO" rev-parse --verify "$ADAPTER_GIT_REF" >/dev/null 2>&1; then
    ADAPTER_GIT_REF="HEAD"
  fi
  echo "Creating temporary git worktree from $ADAPTER_REPO ($ADAPTER_GIT_REF)..."
  rm -rf "$WT_DIR"
  git -C "$ADAPTER_REPO" worktree add --detach "$WT_DIR" "$ADAPTER_GIT_REF" >/dev/null
else
  echo "Cloning https://github.com/firebase/apphosting-adapters.git into temporary directory..."
  CLONED_REPO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apphosting-adapters-clone.XXXXXX")"
  git clone --depth=1 https://github.com/firebase/apphosting-adapters.git "$CLONED_REPO_DIR" >/dev/null
  ADAPTER_REPO="$CLONED_REPO_DIR"
  rm -rf "$WT_DIR"
  git -C "$ADAPTER_REPO" worktree add --detach "$WT_DIR" HEAD >/dev/null
fi

ADAPTER_PKG_DIR="$WT_DIR/packages/@google-cloud/adapter-nextjs"
if [[ ! -d "$ADAPTER_PKG_DIR" ]]; then
  echo "ERROR: packages/@google-cloud/adapter-nextjs not found in $ADAPTER_REPO ($ADAPTER_GIT_REF)" >&2
  exit 1
fi

echo "Building @google-cloud/adapter-nextjs..."
if [[ -d "$ADAPTER_REPO/node_modules" && ! -e "$WT_DIR/node_modules" ]]; then
  ln -s "$ADAPTER_REPO/node_modules" "$WT_DIR/node_modules"
  if [[ -d "$ADAPTER_REPO/packages/@google-cloud/adapter-nextjs/node_modules" ]]; then
    ln -s "$ADAPTER_REPO/packages/@google-cloud/adapter-nextjs/node_modules" "$ADAPTER_PKG_DIR/node_modules"
  fi
  if ! (cd "$WT_DIR" && npm --workspace=@google-cloud/adapter-nextjs run build >/dev/null 2>&1); then
    rm -f "$WT_DIR/node_modules" "$ADAPTER_PKG_DIR/node_modules"
    (cd "$WT_DIR" && npm ci --no-audit --no-fund >/dev/null && npm --workspace=@google-cloud/adapter-nextjs run build >/dev/null)
  fi
else
  (cd "$WT_DIR" && npm ci --no-audit --no-fund >/dev/null && npm --workspace=@google-cloud/adapter-nextjs run build >/dev/null)
fi

TARBALL_NAME="$(cd "$ADAPTER_PKG_DIR" && npm pack --quiet | tail -n 1)"
TARBALL_PATH="$ADAPTER_PKG_DIR/$TARBALL_NAME"

if [[ ! -f "$TARBALL_PATH" ]]; then
  echo "ERROR: npm pack did not produce expected tarball at $TARBALL_PATH" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/.cache"
cp -f "$TARBALL_PATH" "$REPO_ROOT/.cache/$TARBALL_NAME"

for target in "${RESOLVED_TARGETS[@]}"; do
  rm -f "$target"/google-cloud-adapter-nextjs-*.tgz
  cp -f "$TARBALL_PATH" "$target/$TARBALL_NAME"
  echo "Packed adapter copied to: $target/$TARBALL_NAME"
done
