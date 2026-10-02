#!/bin/bash
# Wait until raspine.pistar.uk serves the packages just pushed to gh-pages.
#
# A deploy is a push to gh-pages, after which GitHub Pages rebuilds the site
# and Cloudflare caches it. Purging Cloudflare before the Pages build has
# finished lets it re-cache the old APKINDEX, so clients (and the image
# build) see package versions that no longer exist and get 404s.
#
# This script:
#   1. reads the expected package versions from gh-pages at its current
#      commit (the source of truth for what was just deployed)
#   2. waits for the GitHub Pages build of that commit to finish
#   3. purges Cloudflare (when credentials are set)
#   4. polls the live APKINDEX at the same URLs apk uses until it lists the
#      expected versions and their .apk files download, re-purging while stale
#
# Environment:
#   GH_TOKEN                token for the GitHub API (needs pages:read)
#   GITHUB_REPOSITORY       owner/repo
#   CLOUDFLARE_ZONE_ID      optional, with CLOUDFLARE_API_TOKEN
#   CLOUDFLARE_API_TOKEN    optional
#   REPO_URL                default https://raspine.pistar.uk
#   ALPINE_VERSIONS         default "3.23"
#   ARCHES                  default "armhf aarch64"
#   PACKAGES                default: firmware and kernels used by images
#   TIMEOUT                 seconds, default 1800
#
# Exits 0 when the live repository matches gh-pages, 1 otherwise.

set -euo pipefail

REPO_URL="${REPO_URL:-https://raspine.pistar.uk}"
ALPINE_VERSIONS="${ALPINE_VERSIONS:-3.23}"
ARCHES="${ARCHES:-armhf aarch64}"
PACKAGES="${PACKAGES:-raspios-firmware raspios-kernel-v6 raspios-kernel-v7 raspios-kernel-v8 raspios-kernel-2712}"
TIMEOUT="${TIMEOUT:-1800}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DEADLINE=$(( $(date +%s) + TIMEOUT ))

log() { echo "[wait-for-repo] $*"; }

time_left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

# index_versions FILE -> "name version" lines for the packages we track
index_versions() {
	tar -xzOf "$1" APKINDEX 2>/dev/null | awk -v want=" $PACKAGES " '
		/^P:/ { p = substr($0, 3) }
		/^V:/ { if (index(want, " " p " ")) print p, substr($0, 3) }
	' | sort
}

purge_cloudflare() {
	if [ -z "${CLOUDFLARE_ZONE_ID:-}" ] || [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
		return 0
	fi
	local host="${REPO_URL#https://}"
	curl -s -o /dev/null -X POST \
		"https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
		-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
		-H "Content-Type: application/json" \
		--data "{\"prefixes\": [\"https://${host}/\", \"http://${host}/\"]}"
	log "Cloudflare cache purged for ${host}"
}

# ── 1. Expected versions from gh-pages ───────────────────────────────
SHA=$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/gh-pages" -q .object.sha)
log "gh-pages is at ${SHA}"

for ver in $ALPINE_VERSIONS; do
	for arch in $ARCHES; do
		path="v${ver}/community/${arch}/APKINDEX.tar.gz"
		gh api "repos/${GITHUB_REPOSITORY}/contents/${path}?ref=${SHA}" \
			-H "Accept: application/vnd.github.raw" > "$WORK/expected.tar.gz"
		index_versions "$WORK/expected.tar.gz" > "$WORK/expected-${ver}-${arch}"
		if [ ! -s "$WORK/expected-${ver}-${arch}" ]; then
			log "ERROR: no tracked packages in gh-pages ${path}"
			exit 1
		fi
		log "expected ${ver}/${arch}: $(tr '\n' ' ' < "$WORK/expected-${ver}-${arch}")"
	done
done

# ── 2. GitHub Pages build of that commit ─────────────────────────────
while :; do
	read -r status commit < <(gh api "repos/${GITHUB_REPOSITORY}/pages/builds/latest" \
		-q '.status + " " + .commit' 2>/dev/null || echo "unknown none")
	if [ "$commit" = "$SHA" ] && [ "$status" = "built" ]; then
		log "GitHub Pages build of ${SHA:0:7} is complete"
		break
	fi
	if [ "$commit" = "$SHA" ] && [ "$status" = "errored" ]; then
		log "ERROR: GitHub Pages build of ${SHA:0:7} failed"
		exit 1
	fi
	if ! time_left; then
		log "ERROR: timed out waiting for the GitHub Pages build (latest: ${status} ${commit:0:7})"
		exit 1
	fi
	log "GitHub Pages build: ${status} ${commit:0:7}, waiting for ${SHA:0:7}..."
	sleep 20
done

# ── 3 & 4. Purge, then verify what clients actually receive ──────────
purge_cloudflare
last_purge=$(date +%s)

while :; do
	stale=""
	for ver in $ALPINE_VERSIONS; do
		for arch in $ARCHES; do
			base="${REPO_URL}/v${ver}/community/${arch}"
			if ! curl -fsS -o "$WORK/live.tar.gz" "${base}/APKINDEX.tar.gz"; then
				stale="$stale ${ver}/${arch}:index-unreachable"
				continue
			fi
			index_versions "$WORK/live.tar.gz" > "$WORK/live"
			if ! cmp -s "$WORK/live" "$WORK/expected-${ver}-${arch}"; then
				stale="$stale ${ver}/${arch}:index"
				continue
			fi
			while read -r name version; do
				code=$(curl -s -o /dev/null -I -w '%{http_code}' "${base}/${name}-${version}.apk")
				[ "$code" = "200" ] || stale="$stale ${ver}/${arch}:${name}-${version}=${code}"
			done < "$WORK/expected-${ver}-${arch}"
		done
	done

	if [ -z "$stale" ]; then
		log "Live repository matches gh-pages ${SHA:0:7}"
		exit 0
	fi
	if ! time_left; then
		log "ERROR: live repository still stale after ${TIMEOUT}s:${stale}"
		exit 1
	fi
	log "still stale:${stale}"
	if [ $(( $(date +%s) - last_purge )) -ge 60 ]; then
		purge_cloudflare
		last_purge=$(date +%s)
	fi
	sleep 20
done
