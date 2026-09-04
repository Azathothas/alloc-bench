#!/bin/sh
set -eu

REPO="${1:?usage: fetch-source.sh <repo-url> <commit> <dest>}"
COMMIT="${2:?usage: fetch-source.sh <repo-url> <commit> <dest>}"
DEST="${3:?usage: fetch-source.sh <repo-url> <commit> <dest>}"

command -v git >/dev/null 2>&1 || { echo "fetch: git not found" >&2; exit 2; }

if [ -d "$DEST/.git" ]; then
    have=$(git -C "$DEST" rev-parse HEAD 2>/dev/null || echo none)
    if [ "$have" = "$COMMIT" ]; then
        echo "fetch: $DEST already at $COMMIT"
        exit 0
    fi
    rm -rf "$DEST"
fi

mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" remote add origin "$REPO"

# Fetch the single commit where the server allows it; fall back to a full
# fetch, which is slower and always works.
if ! git -C "$DEST" fetch -q --depth 1 origin "$COMMIT" 2>/dev/null; then
    git -C "$DEST" fetch -q --tags origin || { echo "fetch: could not fetch $REPO" >&2; exit 2; }
fi
git -C "$DEST" checkout -q --detach "$COMMIT" 2>/dev/null || {
    echo "fetch: $REPO has no commit $COMMIT" >&2
    exit 1
}

# Submodules matter: snmalloc and tcmalloc carry dependencies this way, and a
# missing one shows up as a confusing compile error rather than a fetch error.
git -C "$DEST" submodule update -q --init --recursive --depth 1 2>/dev/null || true

got=$(git -C "$DEST" rev-parse HEAD)
if [ "$got" != "$COMMIT" ]; then
    echo "fetch: asked for $COMMIT but HEAD is $got" >&2
    exit 1
fi
echo "fetch: $REPO at $COMMIT -> $DEST"
