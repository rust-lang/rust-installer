#!/bin/sh

set -e -u

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

say() {
    echo "test: $1"
}

pre() {
    echo "test: $1"
    rm -Rf "$WORK_DIR"
    rm -Rf "$OUT_DIR"
    rm -Rf "$PREFIX_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUT_DIR"
    mkdir -p "$PREFIX_DIR"
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

fail() {
    echo
    echo "$1"
    echo
    echo "TEST FAILED!"
    echo
    exit 1
}

try() {
    set +e
    _cmd="$@"
    _output=`$@ 2>&1`
    if [ $? -ne 0 ]; then
	echo \$ "$_cmd"
	# Using /bin/echo to avoid escaping
	/bin/echo "$_output"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    else
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_CMD-}" ]; then
	    echo \$ "$_cmd"
	fi
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_OUTPUT-}" ]; then
	    /bin/echo "$_output"
	fi
    fi
    set -e
}

expect_fail() {
    set +e
    _cmd="$@"
    _output=`$@ 2>&1`
    if [ $? -eq 0 ]; then
	echo \$ "$_cmd"
	# Using /bin/echo to avoid escaping
	/bin/echo "$_output"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    else
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_CMD-}" ]; then
	    echo \$ "$_cmd"
	fi
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_OUTPUT-}" ]; then
	    /bin/echo "$_output"
	fi
    fi
    set -e
}

expect_output_ok() {
    set +e
    local _expected="$1"
    shift 1
    _cmd="$@"
    _output=`$@ 2>&1`
    if [ $? -ne 0 ]; then
	echo \$ "$_cmd"
	# Using /bin/echo to avoid escaping
	/bin/echo "$_output"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    elif ! echo "$_output" | grep -q "$_expected"; then
	echo \$ "$_cmd"
	/bin/echo "$_output"
	echo
	echo "missing expected output '$_expected'"
	echo
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    else
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_CMD-}" ]; then
	    echo \$ "$_cmd"
	fi
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_OUTPUT-}" ]; then
	    /bin/echo "$_output"
	fi
    fi
    set -e
}

expect_output_fail() {
    set +e
    local _expected="$1"
    shift 1
    _cmd="$@"
    _output=`$@ 2>&1`
    if [ $? -eq 0 ]; then
	echo \$ "$_cmd"
	# Using /bin/echo to avoid escaping
	/bin/echo "$_output"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    elif ! echo "$_output" | grep -q "$_expected"; then
	echo \$ "$_cmd"
	/bin/echo "$_output"
	echo
	echo "missing expected output '$_expected'"
	echo
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    else
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_CMD-}" ]; then
	    echo \$ "$_cmd"
	fi
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_OUTPUT-}" ]; then
	    /bin/echo "$_output"
	fi
    fi
    set -e
}

expect_not_output_ok() {
    set +e
    local _expected="$1"
    shift 1
    _cmd="$@"
    _output=`$@ 2>&1`
    if [ $? -ne 0 ]; then
	echo \$ "$_cmd"
	# Using /bin/echo to avoid escaping
	/bin/echo "$_output"
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    elif echo "$_output" | grep -q "$_expected"; then
	echo \$ "$_cmd"
	/bin/echo "$_output"
	echo
	echo "unexpected output '$_expected'"
	echo
	echo
	echo "TEST FAILED!"
	echo
	exit 1
    else
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_CMD-}" ]; then
	    echo \$ "$_cmd"
	fi
	if [ -n "${VERBOSE-}" -o -n "${VERBOSE_OUTPUT-}" ]; then
	    /bin/echo "$_output"
	fi
    fi
    set -e
}

runtest() {
    local _testname="$1"
    if [ -n "${TESTNAME-}" ]; then
	if ! echo "$_testname" | grep -q "$TESTNAME"; then
	    return 0
	fi
    fi

    pre "$_testname"
    "$_testname"
}

# Installation tests

basic_install() {
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
}
runtest basic_install

basic_uninstall() {
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
}
runtest basic_uninstall

not_installed_files() {
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
}
runtest not_installed_files

verify_override() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--verify-bin=program2
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
}
runtest verify_override

tarball_with_package_name() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--package-name=rustc-nightly
    try "$WORK_DIR/rustc-nightly/install.sh" --prefix="$PREFIX_DIR"
    try test -e "$OUT_DIR/rustc-nightly.tar.gz"
}
runtest tarball_with_package_name

bulk_directory() {
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
}
runtest tarball_with_package_name

nested_bulk_directory() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image4" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--bulk-dirs=dir-to-install/qux
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
    try test -e "$PREFIX_DIR/dir-to-install/qux/bar"
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
    try test ! -e "$PREFIX_DIR/dir-to-install/qux"
}
runtest nested_bulk_directory

only_bulk_directory_no_files() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image5" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--bulk-dirs=dir-to-install
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
    try test -e "$PREFIX_DIR/dir-to-install/foo"
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --uninstall
    try test ! -e "$PREFIX_DIR/dir-to-install/foo"
}
runtest only_bulk_directory_no_files

nested_not_installed_files() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image4" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--non-installed-prefixes=dir-to-install/qux/bar
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
    try test ! -e "$PREFIX_DIR/dir-to-install/qux/bar"
}
runtest nested_not_installed_files

# Upgrade tests

upgrade_v1_v2() {
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
}
runtest upgrade_v1_v2

upgrade_v1_v2_with_multiple_legacy_manifests() {
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
}
runtest upgrade_v1_v2_with_multiple_legacy_manifests

multiple_components() {
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
}
runtest multiple_components

# Combined installer tests

combine_installers() {
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
}
runtest combine_installers

combine_three_installers() {
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
}
runtest combine_three_installers

combine_installers_with_overlay() {
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
}
runtest combine_installers_with_overlay

combined_with_bulk_dirs() {
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
}
runtest combined_with_bulk_dirs

combine_install_with_separate_uninstall() {
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
}
runtest combine_install_with_separate_uninstall

combined_v1_v2_upgrade() {
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
}
runtest combined_v1_v2_upgrade

# Smoke tests

cannot_run_bins_error() {
    try sh "$S/gen-installer.sh" \
	--verify-bin=bad-bin \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR"
    expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
}
runtest cannot_run_bins_error

cannot_write_error() {
    # chmod doesn't work on windows
    if [ ! -n "${WINDOWS-}" ]; then
	try sh "$S/gen-installer.sh" \
	    --image-dir="$TEST_DIR/image1" \
	    --work-dir="$WORK_DIR" \
	    --output-dir="$OUT_DIR"
	chmod u-w "$PREFIX_DIR"
	expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
	chmod u+w "$PREFIX_DIR"
    fi
}
runtest cannot_write_error

cannot_install_to_installer() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--package-name=my-package
    expect_fail "$WORK_DIR/my-package/install.sh" --prefix="$WORK_DIR/my-package"
}
runtest cannot_install_to_installer

upgrade_from_future_installer_error() {
    try sh "$S/gen-installer.sh" \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR" \
	--rel-manifest-dir=rustlib
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
    echo 100 > "$PREFIX_DIR/lib/rustlib/rust-installer-version"
    expect_fail "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR"
}
runtest upgrade_from_future_installer_error

disable_verify() {
    try sh "$S/gen-installer.sh" \
	--verify-bin=bad-bin \
	--image-dir="$TEST_DIR/image1" \
	--work-dir="$WORK_DIR" \
	--output-dir="$OUT_DIR"
    try "$WORK_DIR/package/install.sh" --prefix="$PREFIX_DIR" --disable-verify
}
runtest disable_verify

# TODO: DESTDIR
# TODO: mandir/libdir/bindir, etc.

echo
echo "TOTAL SUCCESS!"
echo
