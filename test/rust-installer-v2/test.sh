#!/bin/sh

S="$(cd $(dirname $0) && pwd)"

TEST_DIR="$S/test"
TMP_DIR="$S/tmp"
WORK_DIR="$TMP_DIR/workdir"
OUT_DIR="$TMP_DIR/outdir"
PREFIX_DIR="$TMP_DIR/prefix"

case $(uname -s) in

    MINGW* | MSYS*)
	WINDOWS=1
        ;;
esac

pre() {
    echo
    echo "test: $1"
    echo
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

need_ok() {
    if [ $? -ne 0 ]
    then
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    fi
}

try() {
    cmd="$@"
    echo \$ "$cmd"
    OUTPUT=`$@`
    if [ $? -ne 0 ]; then
	echo
	# Using /bin/echo to avoid escaping
	/bin/echo "$OUTPUT"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    fi
}

expect_fail() {
    cmd="$@"
    echo \$ "$cmd"
    OUTPUT=`$@`
    if [ $? -eq 0 ]; then
	echo
	# Using /bin/echo to avoid escaping
	/bin/echo "$OUTPUT"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    fi
}

# Installation tests

pre "basic install"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
post

pre "basic uninstall"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/package/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

pre "not installed files"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --non-installed-prefixes=something-to-not-install,dir-to-not-install
try test -e "$WORK_DIR/package/something-to-not-install"
try test -e "$WORK_DIR/package/dir-to-not-install"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-not-install"
try test ! -e "$PREFIX_DIR/dir-to-not-install"
post

pre "verify override"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=program2
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
post

pre "tarball with package name"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc-nightly
try "$WORK_DIR/rustc-nightly/install.sh" --prefix="$PREFIX_DIR"
try test -e "$OUT_DIR/rustc-nightly.tar.gz"
post

pre "bulk directory"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --bulk-dirs=dir-to-install
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
try test ! -e "$PREFIX_DIR/dir-to-install"
post

pre "nested bulk directory"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image4" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --bulk-dirs=dir-to-install/qux
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/dir-to-install/qux/bar"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
try test ! -e "$PREFIX_DIR/dir-to-install/qux"
post

pre "only bulk directory, no files"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image5" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --bulk-dirs=dir-to-install
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
post

pre "nested not installed files"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image4" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --non-installed-prefixes=dir-to-install/qux/bar
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/dir-to-install/qux/bar"
post

# Upgrade tests

pre "upgrade v1 -> v2"
mkdir "$WORK_DIR/v1"
try sh "$S/test/rust-installer-v1/gen-installer.sh" \
    --image-dir="$TEST_DIR/image2" \
    --work-dir="$WORK_DIR/v1" \
    --output-dir="$OUT_DIR/v1" \
    --verify-bin=oldprogram \
    --rel-manifest-dir=packagelib
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --rel-manifest-dir=packagelib \
    --legacy-manifest-dirs=packagelib
try "$WORK_DIR/v1/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/bar"
try test -e "$PREFIX_DIR/bin/oldprogram"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/dir-to-install/bar"
try test ! -e "$PREFIX_DIR/bin/oldprogram"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try "$WORK_DIR/package/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

pre "upgrade v1 -> v2 with multiple legacy manifests"
mkdir "$WORK_DIR/v1"
try sh "$S/test/rust-installer-v1/gen-installer.sh" \
    --image-dir="$TEST_DIR/image2" \
    --work-dir="$WORK_DIR/v1" \
    --output-dir="$OUT_DIR/v1" \
    --verify-bin=oldprogram \
    --rel-manifest-dir=rustlib
try sh "$S/test/rust-installer-v1/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR/v1b" \
    --output-dir="$OUT_DIR/v1b" \
    --verify-bin=cargo \
    --rel-manifest-dir=cargo
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --rel-manifest-dir=packagelib \
    --legacy-manifest-dirs=rustlib,cargo
try "$WORK_DIR/v1/package/install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/v1b/package/install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/dir-to-install/bar"
try test ! -e "$PREFIX_DIR/bin/oldprogram"
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/cargo"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try "$WORK_DIR/package/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

pre "multiple components"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR/c1" \
    --output-dir="$OUT_DIR/c1" \
    --component-name=rustc
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR/c2" \
    --output-dir="$OUT_DIR/c2" \
    --verify-bin=cargo \
    --component-name=cargo
try "$WORK_DIR/c1/package/install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/c2/package/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try test -e "$PREFIX_DIR/bin/cargo"
try "$WORK_DIR/c1/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try "$WORK_DIR/c2/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

# Combined installer tests

pre "combine installers"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz"
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try test -e "$PREFIX_DIR/bin/cargo"
try "$WORK_DIR/rust/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

pre "combine three installers"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image4" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust-docs \
    --component-name=rust-docs
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz,$OUT_DIR/rust-docs.tar.gz"
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try test -e "$PREFIX_DIR/bin/cargo"
try test -e "$PREFIX_DIR/dir-to-install/qux/bar"
try "$WORK_DIR/rust/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/packagelib"
try test ! -e "$PREFIX_DIR/dir-to-install/qux/bar"
post

pre "combine installers with overlay"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo
mkdir -p "$WORK_DIR/overlay"
touch "$WORK_DIR/overlay/README"
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz" \
    --non-installed-overlay="$WORK_DIR/overlay"
try test -e "$WORK_DIR/rust/README"
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/README"
post

pre "combined with bulk dirs"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc \
    --bulk-dirs=dir-to-install
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz"
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try "$WORK_DIR/rust/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/dir-to-install"
post

pre "combine install with separate uninstall"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc \
    --rel-manifest-dir=rustlib
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo \
    --rel-manifest-dir=rustlib
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz" \
    --rel-manifest-dir=rustlib
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try test -e "$PREFIX_DIR/bin/cargo"
try "$WORK_DIR/rustc/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try "$WORK_DIR/cargo/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/packagelib"
post

pre "combined v1 -> v2 upgrade"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rustc \
    --component-name=rustc \
    --rel-manifest-dir=rustlib
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --verify-bin=cargo \
    --package-name=cargo \
    --component-name=cargo \
    --rel-manifest-dir=rustlib
try sh "$S/combine-installers.sh" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=rust \
    --input-tarballs="$OUT_DIR/rustc.tar.gz,$OUT_DIR/cargo.tar.gz" \
    --rel-manifest-dir=rustlib \
    --legacy-manifest-dirs=cargo,rustlib
try sh "$S/test/rust-installer-v1/gen-installer.sh" \
    --image-dir="$TEST_DIR/image2" \
    --work-dir="$WORK_DIR/v1" \
    --output-dir="$OUT_DIR/v1" \
    --verify-bin=oldprogram \
    --rel-manifest-dir=rustlib
try sh "$S/test/rust-installer-v1/gen-installer.sh" \
    --image-dir="$TEST_DIR/image3" \
    --work-dir="$WORK_DIR/v1b" \
    --output-dir="$OUT_DIR/v1b" \
    --verify-bin=cargo \
    --rel-manifest-dir=cargo
try "$WORK_DIR/v1/package//install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/v1b/package//install.sh" --prefix="$PREFIX_DIR"
try "$WORK_DIR/rust/install.sh" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/dir-to-install/bar"
try test ! -e "$PREFIX_DIR/bin/oldprogram"
try test ! -e "$PREFIX_DIR/lib/cargo"
try test -e "$PREFIX_DIR/something-to-install"
try test -e "$PREFIX_DIR/dir-to-install/foo"
try test -e "$PREFIX_DIR/bin/program"
try test -e "$PREFIX_DIR/bin/program2"
try test -e "$PREFIX_DIR/bin/bad-bin"
try test -e "$PREFIX_DIR/bin/cargo"
try test -e "$PREFIX_DIR/lib/rustlib"
try "$WORK_DIR/rust/install.sh --uninstall" --prefix="$PREFIX_DIR"
try test ! -e "$PREFIX_DIR/something-to-install"
try test ! -e "$PREFIX_DIR/dir-to-install/foo"
try test ! -e "$PREFIX_DIR/bin/program"
try test ! -e "$PREFIX_DIR/bin/program2"
try test ! -e "$PREFIX_DIR/bin/bad-bin"
try test ! -e "$PREFIX_DIR/bin/cargo"
try test ! -e "$PREFIX_DIR/lib/rustlib"
post

# Smoke tests

pre "can't run bins error"
try sh "$S/gen-installer.sh" \
    --verify-bin=bad-bin \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR"
expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
post

if [ ! -n "$WINDOWS" ]; then
    # chmod doesn't work on windows
    pre "can't write error"
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR"
    chmod u-w "$PREFIX_DIR"
    expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
    chmod u+w "$PREFIX_DIR"
    post
fi

pre "can't install to installer"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --package-name=my-package
expect_fail "$WORK_DIR/my-package/install.sh" --prefix="$WORK_DIR/my-package"
post

pre "upgrade from future installer error"
try sh "$S/gen-installer.sh" \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR" \
    --rel-manifest-dir=rustlib
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
echo 100 > "$PREFIX_DIR/lib/rustlib/rust-installer-version"
expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
post

pre "disable-verify"
try sh "$S/gen-installer.sh" \
    --verify-bin=bad-bin \
    --image-dir="$TEST_DIR/image1" \
    --work-dir="$WORK_DIR" \
    --output-dir="$OUT_DIR"
try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --disable-verify
post

# TODO: DESTDIR
# TODO: mandir/libdir/bindir, etc.

echo
echo "TOTAL SUCCESS!"
echo
