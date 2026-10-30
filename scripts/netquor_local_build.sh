#!/usr/bin/env bash
# Netquor: build the PATCHED web vault on this machine, without Docker (much faster than CI when testing a patch). Nothing is installed globally: it fetches a private Node 24 under
# .netquor-local/ (the web vault builds on Node 24 whatever your own Node is), makes a shallow checkout of the pinned sources, applies netquor-patches/ and runs the same npm build as CI.
#   bash scripts/netquor_local_build.sh            first run (checkout, npm ci, build) or a full clean rebuild
#   bash scripts/netquor_local_build.sh --rebuild  fast loop: keep the checkout and node_modules, reset the sources, re-apply the patches, rebuild (no npm ci)
# Output: .netquor-local/web-vault (what Vaultwarden serves with WEB_VAULT_FOLDER), plus a tarball .netquor-local/bw_web_vault.tar.gz.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="${ROOT}/.netquor-local"
MODE="${1:-full}"
mkdir -p "${WORK}"
start=$(date +%s)
step() { echo "[$(( $(date +%s) - start ))s] $*"; }

if [ ! -x "${WORK}/node24/node_modules/.bin/node" ]; then
    step "fetching a private Node 24"
    npm install --prefix "${WORK}/node24" node@24 --no-audit --no-fund --silent
fi
export PATH="${WORK}/node24/node_modules/.bin:${PATH}"
node --version | grep -q '^v24' || { echo "expected Node 24, got $(node --version)"; exit 1; }
step "using node $(node --version), npm $(npm --version)"

export VAULT_FOLDER="${WORK}/bw_clients" CHECKOUT_TAGS=false
VAULT_VERSION=$(grep -m1 '^ARG VAULT_VERSION=' "${ROOT}/Dockerfile" | cut -d= -f2)
export VAULT_VERSION
if [ "${MODE}" = "--rebuild" ] && [ -d "${VAULT_FOLDER}/.git" ]; then
    step "rebuild: resetting the sources, keeping node_modules"
    git -C "${VAULT_FOLDER}" reset --hard -q
    # a reset keeps files that a patch CREATED (patch 0004 adds one), which would make applying that patch again fail: remove them (ignored files such as node_modules stay)
    git -C "${VAULT_FOLDER}" clean -fdq
else
    step "checking out ${VAULT_VERSION}"
    (cd "${ROOT}" && bash scripts/checkout_web_vault.sh) >/dev/null
fi

step "applying the Netquor patches"
(cd "${ROOT}" && bash scripts/apply_netquor_patches.sh)

cd "${VAULT_FOLDER}"
if [ "${MODE}" = "--rebuild" ] && [ -d node_modules ]; then step "node_modules kept"; else step "npm ci"; npm ci --no-audit --no-fund --loglevel=error; fi
cd apps/web
step "building (npm run dist:oss:selfhost)"
npm run dist:oss:selfhost
printf '{"version":"netquor-local-%s"}' "$(git -C "${ROOT}" rev-parse --short HEAD)" > build/vw-version.json

# update the folder IN PLACE: deleting and recreating it leaves a Docker bind mount pointing at the deleted original (the test server then serves an empty folder)
mkdir -p "${WORK}/web-vault" && rsync -a --delete build/ "${WORK}/web-vault/"
tar -czf "${WORK}/bw_web_vault.tar.gz" -C "${WORK}" web-vault
step "done: ${WORK}/web-vault ($(du -sh "${WORK}/web-vault" | cut -f1)), sha256 $(shasum -a 256 "${WORK}/bw_web_vault.tar.gz" | cut -c1-16)..."
if grep -rlF 'https://alias.netquor.com' "${WORK}/web-vault/app" >/dev/null; then step "proof: the Netquor defaults are in the build"; else echo "ERROR: the build does not contain https://alias.netquor.com"; exit 1; fi
