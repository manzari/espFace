# Release checklist

Ordered steps to publish a version (first: 1.0.0). Everything runs in Docker; nothing here is automated beyond the
tag-triggered Forgejo workflow `.forgejo/workflows/release.yml`, which only builds assets and creates the Forgejo
release. Each registry/store publish is one deliberate command or click.

Canonical repository: `https://git.hauptstadt.monster/manzari/espFace` (public, synced to a mirror).
House rule: **no version number contains the digit 4** (0.3.0 -> 0.5.0, 1.3.0 -> 1.5.0); `check-versions.sh` and
the release workflow enforce it.

Legend: **[account]** needs the user's credentials, **[decision]** needs a decision that is still open.

## Pending decisions

| # | Decision | Status |
|---|---|---|
| 1 | Renderer host domain | Decided 2026-10-14: `https://espface.manzari.dev`. Moved 2026-11-20 to `https://r.espface.manzari.dev` (`/connect/`, `/flash/`, `/docs/`; `/r/1/` stays for devices flashed with 1.0.0, newer firmware serves the renderer from flash). The old host is the landing page and redirects these paths |
| 2 | Monorepo visibility | Decided: make `git.hauptstadt.monster/manzari/espFace` public (user does it) |
| 3 | Mirror host for the Arduino library repo (`ESPFACE_MIRROR_URL`) | **Open** - GitHub, GitLab or Bitbucket, see section 2 |
| 4 | PlatformIO account / owner name the package is published under | **Open** |
| 5 | Play Store, App Store | Deferred after 1.0; 1.0 ships Android via F-Droid only |
| 6 | Android signing key | User creates it (see `apps/mobile/RELEASE.md`) |

## 0. Prepare the version (repo)

1. Bump the version everywhere: `firmware/library.properties`, `firmware/library.json`,
   `firmware/src/core/Platform.h` (`ESPFACE_LIB_VERSION`), `web/package.json`, `tools/fake-device/package.json`,
   `docs/site/package.json` (the app version in `apps/mobile/pubspec.yaml` follows `apps/mobile/RELEASE.md`).
2. Add the `## [x.y.z] - date` section to `CHANGELOG.md` and `firmware/CHANGELOG.md`.
3. Check locally:
   ```
   sh tools/release/check-versions.sh v1.0.0
   docker run --rm -v "$PWD":/w -w /w/firmware -v espface-pio:/pio espface-pio test -e native
   docker run --rm -v "$PWD":/w -w /w/firmware -v espface-pio:/pio --entrypoint sh espface-pio tools/ci-build.sh esp32dev
   web/scripts/node.sh sh -c 'npm ci && npm run build && npm test && npm run freeze'
   docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/w -w /w/firmware --entrypoint python3 espface-pio tools/embed-web.py   # embed.h must be committed fresh
   ```
4. Merge to `main`, wait for CI to be green (includes the `renderer-v1-freeze` job).

## 1. Tag and Forgejo release **[account]**

Needs a repository secret `RELEASE_TOKEN` (Forgejo access token with `write:repository`), set once under
repository Settings -> Actions -> Secrets.

```
git tag -a v1.0.0 -m "espFace 1.0.0" && git push origin v1.0.0
```

`release.yml` then: guard (tag has no 4, all versions equal the tag) -> library zip + PlatformIO tarball + arduino-lint
-> footprint report for all chips -> renderer and docs tarballs -> `SHA256SUMS` -> Forgejo release `v1.0.0` with the
`CHANGELOG.md` section as notes. Assets: `espFace-1.0.0.zip` (Arduino IDE "Add .ZIP Library"), `espFace-1.0.0.tar.gz`
(PlatformIO), `espface-renderer-v1.0.0.tar.gz`, `espface-docs-v1.0.0.tar.gz`, `footprint-v1.0.0.md`, `SHA256SUMS`.

## 2. Arduino Library Manager **[account] [decision]**

Library Manager requirements (arduino/library-registry FAQ, checked 2026-10-14):

- `library.properties` must be at the **root** of the repository. In the monorepo it is in `firmware/`.
- The repository must be hosted on **GitHub, GitLab or Bitbucket** ("other hosting sites may be considered on request").
  A self-hosted Forgejo is not on that list.
- Releases are git tags; the indexer polls the registered URL hourly. The name `espFace` must be unused (checked
  2026-10-14: free, no case-insensitive match among 10156 libraries).

So the monorepo cannot be registered directly, even when public and mirrored. Use a dedicated library repository
whose root is the library, kept on hauptstadt.monster as the source and push-mirrored to a supported host:

1. **[account]** On `git.hauptstadt.monster` create the public repo `manzari/espFace-arduino` (empty).
2. **[account] [decision]** Create an empty public repo on the mirror host, e.g. `https://github.com/<user>/espFace`.
   This URL is `ESPFACE_MIRROR_URL`.
3. **[account]** In `manzari/espFace-arduino` on Forgejo: Settings -> Repository -> **Mirror settings** -> Push mirror:
   remote URL = `ESPFACE_MIRROR_URL` (`.git` URL), username + access token of the mirror host (GitHub: fine-grained token
   with Contents read/write on that repo), tick "Sync when commits are pushed", interval e.g. 8h. Push mirrors sync all
   branches and tags.
4. Export, commit and tag the library tree (lint runs on the export; LP042 checks that `url=` resolves, so the
   monorepo must be public first):
   ```
   sh tools/release/split-library.sh export
   docker build -t espface-arduino-lint -f docker/arduino-lint.Dockerfile docker
   docker run --rm -v "$PWD/build/release/espFace":/lib/espFace espface-arduino-lint --library-manager submit --compliance strict /lib/espFace
   ESPFACE_LIB_REMOTE=https://git.hauptstadt.monster/manzari/espFace-arduino.git ESPFACE_MIRROR_URL=https://github.com/<user>/espFace \
     sh tools/release/split-library.sh push                  # dry run: commits + tags v1.0.0 in build/release/espFace-repo
   ESPFACE_LIB_REMOTE=... ESPFACE_PUSH=1 sh tools/release/split-library.sh push   # really pushes main + v1.0.0
   ```
   Check that the mirror shows the commit and tag `v1.0.0`.
5. **[account]** First release only: fork `https://github.com/arduino/library-registry`, add the line
   `https://github.com/<user>/espFace` (the **mirror** URL, not the Forgejo URL) to `repositories.txt`, open the PR and
   follow the bot. Later releases need only step 4: the indexer picks up new tags.

Alternative if the user wants no second Forgejo repo: run `split-library.sh push` with `ESPFACE_LIB_REMOTE` set
directly to the mirror host's repository (token in the git credential helper). The registered URL is the same.

## 3. PlatformIO registry **[account] [decision]**

The registry takes the packed tarball, so the git host does not matter. Name `espFace` is free (registry search
2026-10-14: 0 results).

```
docker run --rm -v "$PWD":/w -w /w/firmware -v espface-pio:/pio espface-pio pkg pack -o /w/build/release/
docker run --rm -it -v "$PWD":/w -w /w -v espface-pio:/pio espface-pio account login       # once, stores the session in the volume
docker run --rm -it -v "$PWD":/w -w /w -v espface-pio:/pio espface-pio pkg publish build/release/espFace-1.0.0.tar.gz --owner <pio-user> --no-interactive
```

Or use the `espFace-1.0.0.tar.gz` asset of the Forgejo release. The tarball contains `src/`, `examples/`,
`library.json`, `library.properties`, `README.md`, `LICENSE`, `CHANGELOG.md` (the `export.include` list in
`library.json`); no tests, tools, `.pio`, `test_output` or footprint files. Check the listing with
`tar tzf build/release/espFace-1.0.0.tar.gz` before publishing; a published version cannot be overwritten, only
unpublished within the registry's grace period (`pio pkg unpublish <owner>/espFace@1.0.0`).

## 4. Renderer and docs host (Coolify) **[account]**

Host: `https://r.espface.manzari.dev`. The `server/renderer` image serves `/`, `/r/1/`, `/connect/`, `/flash/`
and `/docs/`; setup is in `server/renderer/README.md`.

`https://espface.manzari.dev` was the renderer host until 2026-11-20 and is the landing page now (`promo/`, its own
Docker Compose resource with base directory `/promo`). Firmware 1.0.0 loads `https://espface.manzari.dev/r/1/app.js`,
so the landing page redirects `/r/`, `/connect/`, `/flash/` and `/docs/` to the renderer host
(`promo/renderer-host.conf`); a landing page deploy without that redirect breaks those devices.

1. Verify locally:
   ```
   docker build -f server/renderer/Dockerfile -t espface-renderer .
   docker run --rm -d --name espface-renderer-check -p 8081:80 espface-renderer
   curl -sI http://localhost:8081/r/1/app.js      # 200, Cache-Control immutable, Access-Control-Allow-Origin *
   docker stop espface-renderer-check
   ```
2. In the Coolify UI: the Docker Compose resource from this repo (`/server/renderer/docker-compose.yml`), domain
   `https://r.espface.manzari.dev`, branch `main` (or the tag). Press **Deploy** (or let the git webhook do it).
   Never change the server by hand.
3. Check `https://r.espface.manzari.dev/r/1/app.js` and the footer of the system page (renderer version), `/docs/`.
   `curl -sI https://espface.manzari.dev/r/1/app.js` must answer 301 to that URL with `Access-Control-Allow-Origin: *`.
4. `/r/1/` is frozen: read `web/RENDERER-VERSIONING.md` before any renderer change.

## 5. Docs

The docs site ships inside the renderer image (step 4) at `/docs/`; the version in the nav comes from
`docs/site/package.json`. The `espface-docs-v1.0.0.tar.gz` release asset is a static copy for other hosts.

## 6. Android via F-Droid **[account]**

1.0 ships Android through the user's own F-Droid repository. Steps, signing and the version code are in
[`apps/mobile/RELEASE.md`](../apps/mobile/RELEASE.md). The release signing key is created and kept by the user.

## 7. Google Play - deferred

Not part of 1.0. When it happens: [`apps/mobile/RELEASE.md`](../apps/mobile/RELEASE.md).

## 8. Apple App Store - deferred

Not part of 1.0 (needs a Mac and the Apple developer account). When it happens:
[`apps/mobile/RELEASE.md`](../apps/mobile/RELEASE.md).

## After the release

- Set `docs/PLAN.md` phase 7 to done with the date.
- Open an `## [Unreleased]` section in both changelogs (already present in `CHANGELOG.md`).
