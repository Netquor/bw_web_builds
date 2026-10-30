#!/usr/bin/env bash
# Netquor: apply our patches (netquor-patches/*.patch, in file name order) to the checked-out web vault sources. Runs after checkout_web_vault.sh and before the build (build_web_vault.sh calls it).
# A patch that no longer applies FAILS the build: we never ship a half-patched web vault. A patch that is already applied (a second run on the same checkout) is skipped.
set -o pipefail -o errexit
BASEDIR=$(RL=$(readlink -n "$0"); SP="${RL:-$0}"; dirname "$(cd "$(dirname "${SP}")"; pwd)/$(basename "${SP}")")
# shellcheck source=scripts/.script_env
. "${BASEDIR}/.script_env"
PATCHDIR="${BASEDIR}/../netquor-patches"
shopt -s nullglob
patches=("${PATCHDIR}"/*.patch)
if [ "${#patches[@]}" -eq 0 ]; then echo "Netquor: no patches found in ${PATCHDIR}"; exit 0; fi
for p in "${patches[@]}"; do
    if git -C "${VAULT_FOLDER}" apply --check --reverse "$p" 2>/dev/null; then
        echo "Netquor: $(basename "$p") is already applied, skipping"
        continue
    fi
    echo "Netquor: applying $(basename "$p") to ${VAULT_FOLDER}"
    git -C "${VAULT_FOLDER}" apply --check "$p"
    git -C "${VAULT_FOLDER}" apply "$p"
done
