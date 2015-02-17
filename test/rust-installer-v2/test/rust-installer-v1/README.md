A generator for the install.sh script commonly used to install Rust in
Unix environments. It is used By Rust, Cargo, and is intended to be
used by a future combined installer of Rust + Cargo.

# Usage

```
./gen-installer.sh --product-name=Rust \
                   --verify-bin=rustc \
                   --rel-manifest-dir=rustlib \
                   --success-message=Rust-is-ready-to-roll. \
                   --image-dir=./install-image \
                   --work-dir=./temp \
                   --output-dir=./dist \
                   --non-installed-prefixes="foo,bin/bar,lib/baz" \
                   --package-name=rustc-nightly-i686-apple-darwin
```

Or, to just generate the script.

```
./gen-install-script.sh --product-name=Rust \
                        --verify-bin=rustc \
                        --rel-manifest-dir=rustlib \
                        --success-message=Rust-is-ready-to-roll. \
                        --output-script=install.sh
```

*Note: the dashes in `success-message` are converted to spaces. The
script's argument handling is broken with spaces.*