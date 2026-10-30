#!/usr/bin/env bash
# Netquor upstream watcher (daily by .github/workflows/netquor-watch.yml, or by hand: `bash scripts/netquor_watch.sh`, needs `gh` logged in).
# Compares what we are based on (netquor-patches/BASE) with the newest upstream releases and writes a report: which web vault / server release is new, which of the files WE depend on changed
# between the two (netquor-patches/WATCHED.txt, SERVER_WATCHED.txt), and whether our patches still apply to the new sources. In GitHub Actions it opens ONE issue per new release pair; nothing is deployed.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
. netquor-patches/BASE
WEB=dani-garcia/bw_web_builds; SRC=vaultwarden/vw_web_builds; SRV=dani-garcia/vaultwarden
out=$(mktemp); findings=0
say() { echo "$*" >>"$out"; }
fetch() { gh api "repos/$1/contents/$2?ref=$3" --jq .content 2>/dev/null | base64 -d 2>/dev/null; }   # file at a ref (empty if it does not exist there)

latest_web=$(gh api "repos/$WEB/releases/latest" --jq .tag_name)
latest_srv=$(gh api "repos/$SRV/releases/latest" --jq .tag_name)
say "## Netquor upstream watch, $(date -u +%F)"
say ""
say "| | we run | newest upstream |"
say "|---|---|---|"
say "| web vault | $WEB_VAULT_TAG | $latest_web |"
say "| server | $SERVER_TAG | $latest_srv |"
say ""
say "Last reviewed: $REVIEWED. Nothing is deployed automatically: read this, run the staging check, then bump \`netquor-patches/BASE\` and the pinned tag in the Vaultwarden compose file."

if [ "$latest_web" != "$WEB_VAULT_TAG" ]; then
    findings=1
    new_commit=$(fetch "$WEB" Dockerfile "$latest_web" | grep -m1 '^ARG VAULT_VERSION=' | cut -d= -f2)
    say ""; say "### Web vault $WEB_VAULT_TAG to $latest_web"
    say "- Release: https://github.com/$WEB/releases/tag/$latest_web"
    say "- Bitwarden clients commit it pins: \`$new_commit\` (we are on \`$WEB_VAULT_COMMIT\`). Changes: https://github.com/$SRC/compare/$WEB_VAULT_COMMIT...$new_commit"
    work=$(mktemp -d); git -C "$work" init -q
    say ""; say "Files our patches touch:"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in \#*) continue ;; esac
        mkdir -p "$work/$(dirname "$f")"
        fetch "$SRC" "$f" "$new_commit" > "$work/$f" || true
        if [ ! -s "$work/$f" ]; then say "- \`$f\`: **missing in the new version** (moved or removed): our patch needs rewriting"; continue; fi
        if [ "$(fetch "$SRC" "$f" "$WEB_VAULT_COMMIT" | shasum -a 256 | cut -d' ' -f1)" = "$(shasum -a 256 < "$work/$f" | cut -d' ' -f1)" ]; then say "- \`$f\`: unchanged"; else say "- \`$f\`: **changed upstream**"; fi
    done < netquor-patches/WATCHED.txt
    say ""; say "Do our patches still apply to the new sources?"
    for p in netquor-patches/*.patch; do
        if git -C "$work" apply --check "$PWD/$p" 2>/dev/null; then say "- \`$(basename "$p")\`: applies cleanly"; else say "- \`$(basename "$p")\`: **DOES NOT APPLY**: rewrite it before building this release"; fi
    done
fi

if [ "$latest_srv" != "$SERVER_TAG" ]; then
    findings=1
    say ""; say "### Server $SERVER_TAG to $latest_srv"
    say "- Release notes: https://github.com/$SRV/releases/tag/$latest_srv"
    say "- Full diff: https://github.com/$SRV/compare/$SERVER_TAG...$latest_srv"
    cmp=$(mktemp); gh api "repos/$SRV/compare/$SERVER_TAG...$latest_srv" > "$cmp" 2>/dev/null || echo '{}' > "$cmp"
    say ""; say "Files Netquor depends on (CSP and options, SSO, the organization import our sync uses):"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in \#*) continue ;; esac
        info=$(jq -r --arg f "$f" '.files[]? | select(.filename==$f) | "+\(.additions) -\(.deletions)"' "$cmp")
        if [ -n "$info" ]; then say "- \`$f\`: **changed** ($info)"; else say "- \`$f\`: unchanged"; fi
    done < netquor-patches/SERVER_WATCHED.txt
fi

if [ "$findings" = 0 ]; then say ""; say "Nothing new upstream."; fi
cat "$out"
if [ "$findings" = 1 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    title="Upstream update to review: web vault $latest_web, server $latest_srv"
    if [ "$(gh issue list --state open --search "in:title \"$title\"" --json number --jq length)" = 0 ]; then gh issue create --title "$title" --body-file "$out"; fi
fi
