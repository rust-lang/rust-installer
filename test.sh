#!/bin/sh

S="$(cd $(dirname $0) && pwd)"

TEST_DIR="$S/test"
WORK_DIR="$TEST_DIR/workdir"
OUT_DIR="$TEST_DIR/outdir"
PREFIX_DIR="$TEST_DIR/prefix"

pre() {
    echo "test: $1"
    rm -Rf "$WORK_DIR"
    rm -Rf "$OUT_DIR"
    rm -Rf "$PREFIX_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUT_DIR"
    mkdir -p "$PREFIX_DIR"
}

post() {
    rm -Rf "$WORK_DIR"
    rm -Rf "$OUT_DIR"
    rm -Rf "$PREFIX_DIR"
}

try() {
    cmd="$@"
    echo \$ "$cmd"
    $@ > /dev/null
    if [ $? -ne 0 ]; then
	echo "command failed: '$cmd'"
	exit 1
    fi
}

pre "install / uninstall v1"
try sh "$S/gen-installer.sh" \
    --product-name=Rust \
    --verify-bin=rustc \
    --rel-manifest-dir=rustlib \
    --success-message=Rust-is-ready-to-roll. \
    --image-dir="$TEST_DIR/repo1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --non-installed-prefixes=something-to-not-install,dir-to-not-install \
    --package-name=rustc-nightly \
    --component-name=rustc
try "$WORK_DIR/rustc-nightly/install.sh" --prefix="$PREFIX_DIR"
try test -f "$PREFIX_DIR/something-to-install"
try test -f "$PREFIX_DIR/dir-to-install/foo"
post
