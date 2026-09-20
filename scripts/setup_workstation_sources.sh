#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/SCA-AIFNav-Project"

AIMAPP_URL="https://github.com/MarsRemmer/aimapp.git"
HOUSE_URL="https://github.com/MarsRemmer/aws-robomaker-small-house-world.git"
WAREHOUSE_URL="https://github.com/MarsRemmer/aws-robomaker-small-warehouse-world.git"
SCA_URL="https://github.com/MarsRemmer/SCA-AIFNav.git"

AIMAPP_BRANCH="reproduction"
HOUSE_BRANCH="sca-aifnav-env"
WAREHOUSE_BRANCH="sca-aifnav-env"
SCA_BRANCH="main"

AIMAPP_EXPECTED="20746e0"
HOUSE_EXPECTED="13eeab7"
WAREHOUSE_EXPECTED="6baf3ab"
SCA_EXPECTED="a29db95"

mkdir -p \
  "$ROOT/aimapp/runtime_ws/src" \
  "$ROOT/sca_aifnav/runtime_ws/src" \
  "$ROOT/results"

clone_or_check() {
  local url="$1"
  local branch="$2"
  local dst="$3"
  local expected="$4"

  if [[ -d "$dst/.git" ]]; then
    echo "[EXISTS] $dst"
  else
    echo "[CLONE] $url -> $dst"
    git clone --branch "$branch" --single-branch "$url" "$dst"
  fi

  git -C "$dst" fetch origin "$branch"
  git -C "$dst" checkout "$branch"

  local head
  head="$(git -C "$dst" rev-parse --short=7 HEAD)"

  echo "[HEAD] $dst -> $head"

  if [[ "$head" != "$expected" ]]; then
    echo "ERROR: unexpected commit for $dst"
    echo "Expected: $expected"
    echo "Actual  : $head"
    exit 1
  fi
}

clone_or_check \
  "$AIMAPP_URL" \
  "$AIMAPP_BRANCH" \
  "$ROOT/aimapp/runtime_ws/src/aimapp" \
  "$AIMAPP_EXPECTED"

clone_or_check \
  "$HOUSE_URL" \
  "$HOUSE_BRANCH" \
  "$ROOT/aimapp/runtime_ws/src/aws-robomaker-small-house-world" \
  "$HOUSE_EXPECTED"

clone_or_check \
  "$WAREHOUSE_URL" \
  "$WAREHOUSE_BRANCH" \
  "$ROOT/aimapp/runtime_ws/src/aws-robomaker-small-warehouse-world" \
  "$WAREHOUSE_EXPECTED"

clone_or_check \
  "$SCA_URL" \
  "$SCA_BRANCH" \
  "$ROOT/sca_aifnav/runtime_ws/src/sca_aifnav" \
  "$SCA_EXPECTED"

add_upstream_if_missing() {
  local repo="$1"
  local url="$2"

  if git -C "$repo" remote get-url upstream >/dev/null 2>&1; then
    true
  else
    git -C "$repo" remote add upstream "$url"
  fi
}

add_upstream_if_missing \
  "$ROOT/aimapp/runtime_ws/src/aimapp" \
  "https://github.com/decide-ugent/aimapp.git"

add_upstream_if_missing \
  "$ROOT/aimapp/runtime_ws/src/aws-robomaker-small-house-world" \
  "https://github.com/aws-robotics/aws-robomaker-small-house-world.git"

add_upstream_if_missing \
  "$ROOT/aimapp/runtime_ws/src/aws-robomaker-small-warehouse-world" \
  "https://github.com/aws-robotics/aws-robomaker-small-warehouse-world.git"

echo
echo "SOURCE RESTORE PASSED"
echo "Root: $ROOT"
