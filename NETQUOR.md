# Netquor changes to the Vaultwarden web vault builder

This is Netquor's fork of [`dani-garcia/bw_web_builds`](https://github.com/dani-garcia/bw_web_builds), the scripts that build the Bitwarden web vault for Vaultwarden. **Everything Netquor added is on the `netquor` branch** (the fork's default branch) and is listed here; `master` is kept identical to upstream. Written 2026-10-30. Internal notes and the reasons: `docs/vaultwarden-fork-plan.md` in the QUOR repository.

## What differs from upstream

| Path | What | Why |
| --- | --- | --- |
| `netquor-patches/0001-addyio-defaults.patch` | In `libs/tools/generator/core/src/metadata/email/forwarder.ts` (the code that gives every forwarder its starting values, blank upstream): for **Addy.io only**, start with self-host URL `https://alias.netquor.com` and domain `nqvia.com`. The API key stays empty: it is each person's own. | Staff use our own addy.io; this saves them two of the three fields. Web vault only: the extension and mobile apps are Bitwarden's and cannot be changed. **Lesson (2026-10-30):** Bitwarden has two code paths for forwarder defaults; the older `defaultSettings` in `integration/addy-io.ts` is NOT what the generator screen reads any more, so a first version of this patch that changed it had no visible effect. |
| `netquor-patches/0002-netquor-connect-button.patch` | In the generator's forwarder settings: when the self-host URL is `https://alias.netquor.com`, a button **"Get my key from Netquor Aliases"** opens `https://alias.netquor.com/netquor/connect` in a pop-up (the person is already signed in through Authentik); the page creates their addy.io key and hands it back with `postMessage`. The web vault accepts a message only from that exact origin **and** that very pop-up, fills the token field and saves. | Staff get their key without visiting addy.io's settings and copying it. Web vault only. |
| `netquor-patches/0003-netquor-auto-key.patch` | **Silent version of the button.** When the generator is on our addy.io with an empty key, the web vault asks `https://alias.netquor.com/netquor/key` in the background (`fetch` with `credentials: "include"`, header `X-Requested-With: netquor-vault`, body `{"label":"web"}`) and fills the key it gets back. It works because this site and alias.netquor.com are the **same site**, so the person's existing alias sign-in cookie is sent. **Any failure is silent** (no session yet, redirected to sign-in, offline): the button from 0002 stays. At most one try per 10 minutes and component; it never overwrites a key already there. | Staff do nothing. The extension and phone apps cannot be patched, so they use the connect page. |
| `scripts/apply_netquor_patches.sh` (new) | Applies `netquor-patches/*.patch` to the checked-out sources, in name order, and fails the build if one does not apply. | We never ship a half-patched web vault. |
| `scripts/build_web_vault.sh` (+3 lines) | Calls the script above after the checkout and before `npm ci`. | |
| `Dockerfile` (+2 lines) | `COPY netquor-patches` into the build. | |
| `netquor-patches/BASE`, `WATCHED.txt`, `SERVER_WATCHED.txt` | The upstream release we are based on, and the source files we depend on. | Read by the watcher. |
| `scripts/netquor_watch.sh`, `.github/workflows/netquor-watch.yml` | Daily: compares our base with the newest upstream web vault and Vaultwarden server releases, lists which watched files changed, checks our patches still apply to the new sources, and opens **one issue** per new release. | "See what changed, then act." Nothing is deployed from it. |
| `scripts/netquor_local_build.sh` (new), `.gitignore` | Builds the patched web vault on a laptop without Docker: a private Node 24, a shallow checkout, our patches, the same npm build (about 2 minutes; `--rebuild` about 1.5 minutes). | CI takes much longer; this is the test loop. |
| `.github/workflows/netquor-build.yml` | Builds with the patches, proves the patch is in the output, and on a tag `netquor-*` publishes the tarball and its sha256 as a GitHub release. | |

The upstream files `ci.yml`, `hadolint.yml` and `release.yml` are untouched.

## Our base

`netquor-patches/BASE`: web vault **v2026.7.0** (the version bundled with the Vaultwarden server we run, 1.37.4: we do not run a web vault newer than the server's own).

## Local builds (the fast test loop)

`bash scripts/netquor_local_build.sh` (first run: private Node 24, shallow checkout of the pinned sources, `npm ci`, build, about 2 minutes), then `bash scripts/netquor_local_build.sh --rebuild` after editing a patch (resets the sources, re-applies every patch, rebuilds without `npm ci`, about 1.5 minutes). Output: `.netquor-local/web-vault`. To try it: run a throwaway Vaultwarden with `WEB_VAULT_FOLDER` pointing at that folder, or unpack the CI tarball the same way. To edit a patch: change the files under `.netquor-local/bw_clients`, `git diff -- <files>` into `netquor-patches/`, and rebuild.

## Building and releasing

1. Push to `netquor` (or run "Netquor web vault build" by hand): a test build, kept as an artifact.
2. Tag `netquor-<web vault tag>-<n>`, for example `netquor-v2026.7.0-1`: the build is attached to a release with its sha256.
3. Deploy: unpack `bw_web_vault.tar.gz` on the Vaultwarden host, mount the `web-vault` folder into the container and set `WEB_VAULT_FOLDER` to it (`directory/vaultwarden/compose.yaml` in the QUOR repository). **Rollback**: remove the mount and the setting, and the stock web vault inside the image is served again.

## Moving to a new upstream release

The watcher's issue tells you what changed. Then: merge upstream's tag into `netquor` (`git fetch upstream --tags && git merge v<new>`), rewrite any patch that no longer applies (patches are made with `git diff` against the Bitwarden clients commit pinned in the `Dockerfile`), update `netquor-patches/BASE`, build, test on the staging container, tag, deploy, close the issue.

## Adding a patch

Check out the pinned commit of `vaultwarden/vw_web_builds` (the `VAULT_VERSION` in the `Dockerfile`), change the files, `git diff > netquor-patches/000N-what-it-does.patch`, add the touched paths to `netquor-patches/WATCHED.txt`, put a line in the table above saying what and why, build.

## Licence

Upstream is GPL-3.0; our changes are published here under the same licence. The Vaultwarden server (AGPL-3.0) is not modified by us.
