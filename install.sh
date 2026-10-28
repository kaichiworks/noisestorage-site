#!/bin/bash
# Installs or updates the NoiseStorage server on an Ubuntu VPS. Run it as root:
#   curl -fsSL https://noisestorage.com/install.sh | sudo bash
# It downloads the latest release from GitHub (setup.sh and the server for this CPU), checks the release signature
# and the SHA-256 of each file, then runs setup.sh, which asks a few questions (spec v0.15 §3.1).
# Options are passed on to setup.sh, e.g. for automation:
#   curl -fsSL https://noisestorage.com/install.sh | sudo bash -s -- --path wireguard --advertise wg.example.com:51820 --yes
set -euo pipefail

REPO=https://github.com/kaichiworks/noisestorage-server
# The public half of the release signing key, as an ssh-keygen allowed_signers line (docs/ops/release-server.md)
SIGNER=''

fail() {
    echo "error: $*" >&2
    exit 1
}

# Called on the last line, so that a download cut short runs nothing
main() {
    [ "$(id -u)" -eq 0 ] || fail "run as root: curl -fsSL https://noisestorage.com/install.sh | sudo bash"
    command -v curl >/dev/null || fail "curl is required (apt install curl)"
    command -v ssh-keygen >/dev/null || fail "ssh-keygen is required to check the signature (apt install openssh-client)"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|aarch64) ;;
        *) fail "unsupported CPU: $ARCH (x86_64 and aarch64 are supported)" ;;
    esac

    # The latest release, fixed once so that every file comes from the same one
    LATEST=$(curl -fsSIL --proto '=https' -o /dev/null -w '%{url_effective}' "$REPO/releases/latest") \
        || fail "cannot reach $REPO"
    TAG=${LATEST##*/}
    case "$LATEST" in
        */releases/tag/*) ;;
        *) fail "no release found at $REPO/releases" ;;
    esac
    case "$TAG" in
        ''|*[!A-Za-z0-9._-]*) fail "unexpected release name: $TAG" ;;
    esac
    echo "NoiseStorage server $TAG"
    DIR=$(mktemp -d)
    trap 'rm -rf "$DIR"' EXIT
    for file in SHA256SUMS SHA256SUMS.sig setup.sh "e2e-server-$ARCH"; do
        curl -fsSL --proto '=https' -o "$DIR/$file" "$REPO/releases/download/$TAG/$file" || fail "download failed: $file"
    done

    # SHA256SUMS is trusted only with a valid signature; the files only when they match it
    echo "$SIGNER" > "$DIR/allowed_signers"
    ssh-keygen -Y verify -f "$DIR/allowed_signers" -I noisestorage-release -n noisestorage-release \
        -s "$DIR/SHA256SUMS.sig" < "$DIR/SHA256SUMS" >/dev/null \
        || fail "the release signature is not valid. Nothing was installed"
    [ "$(grep -c -E "  (setup\.sh|e2e-server-$ARCH)\$" "$DIR/SHA256SUMS")" -eq 2 ] \
        || fail "SHA256SUMS does not list setup.sh and e2e-server-$ARCH. Nothing was installed"
    (cd "$DIR" && grep -E "  (setup\.sh|e2e-server-$ARCH)\$" SHA256SUMS | sha256sum -c --quiet -) \
        || fail "a downloaded file does not match the signed SHA256SUMS. Nothing was installed"
    echo "signature and checksums: OK"
    echo
    bash "$DIR/setup.sh" "$@"
}

main "$@"
