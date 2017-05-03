// Copyright 2017 The Rust Project Developers. See the COPYRIGHT
// file at the top-level directory of this distribution and at
// http://rust-lang.org/COPYRIGHT.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

use std::fs;
use std::io::{self, Write};

// Needed to set the script mode to executable.
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
// FIXME: what about Windows?  Are default ACLs executable?

const TEMPLATE: &'static str = include_str!("../install-template.sh");

#[derive(Debug)]
pub struct Scripter {
    product_name: String,
    rel_manifest_dir: String,
    success_message: String,
    legacy_manifest_dirs: String,
    output_script: String,
}

impl Default for Scripter {
    fn default() -> Scripter {
        Scripter {
            product_name: "Product".into(),
            rel_manifest_dir: "manifestlib".into(),
            success_message: "Installed.".into(),
            legacy_manifest_dirs: "".into(),
            output_script: "install.sh".into(),
        }
    }
}

impl Scripter {
    /// The name of the product, for display
    pub fn product_name(&mut self, value: String) -> &mut Self {
        self.product_name = value;
        self
    }

    /// The directory under lib/ where the manifest lives
    pub fn rel_manifest_dir(&mut self, value: String) -> &mut Self {
        self.rel_manifest_dir = value;
        self
    }

    /// The string to print after successful installation
    pub fn success_message(&mut self, value: String) -> &mut Self {
        self.success_message = value;
        self
    }

    /// Places to look for legacy manifests to uninstall
    pub fn legacy_manifest_dirs(&mut self, value: String) -> &mut Self {
        self.legacy_manifest_dirs = value;
        self
    }

    /// The name of the output script
    pub fn output_script(&mut self, value: String) -> &mut Self {
        self.output_script = value;
        self
    }

    /// Generate the actual installer script
    pub fn run(self) -> io::Result<()> {
        // Replace dashes in the success message with spaces (our arg handling botches spaces)
        // (TODO: still needed?  kept for compatibility for now...)
        let product_name = self.product_name.replace('-', " ");

        // Replace dashes in the success message with spaces (our arg handling botches spaces)
        // (TODO: still needed?  kept for compatibility for now...)
        let success_message = self.success_message.replace('-', " ");

        let script = TEMPLATE
            .replace("%%TEMPLATE_PRODUCT_NAME%%", &sh_quote(&product_name))
            .replace("%%TEMPLATE_REL_MANIFEST_DIR%%", &self.rel_manifest_dir)
            .replace("%%TEMPLATE_SUCCESS_MESSAGE%%", &sh_quote(&success_message))
            .replace("%%TEMPLATE_LEGACY_MANIFEST_DIRS%%", &sh_quote(&self.legacy_manifest_dirs))
            .replace("%%TEMPLATE_RUST_INSTALLER_VERSION%%", &sh_quote(&::RUST_INSTALLER_VERSION));

        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true);
        if cfg!(unix) {
            options.mode(0o755);
        }
        let output = options.open(self.output_script)?;
        writeln!(&output, "{}", script)
    }
}

fn sh_quote<T: ToString>(s: &T) -> String {
    // We'll single-quote the whole thing, so first replace single-quotes with
    // '"'"' (leave quoting, double-quote one `'`, re-enter single-quoting)
    format!("'{}'", s.to_string().replace('\'', r#"'"'"'"#))
}
