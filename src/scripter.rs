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
use std::io::Write;

// Needed to set the script mode to executable.
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
// FIXME: what about Windows?  Are default ACLs executable?

use errors::*;

const TEMPLATE: &'static str = include_str!("../install-template.sh");


actor!{
    #[derive(Debug)]
    pub struct Scripter {
        /// The name of the product, for display
        product_name: String = "Product",

        /// The directory under lib/ where the manifest lives
        rel_manifest_dir: String = "manifestlib",

        /// The string to print after successful installation
        success_message: String = "Installed.",

        /// Places to look for legacy manifests to uninstall
        legacy_manifest_dirs: String = "",

        /// The name of the output script
        output_script: String = "install.sh",
    }
}

impl Scripter {
    /// Generate the actual installer script
    pub fn run(self) -> Result<()> {
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
        #[cfg(unix)] options.mode(0o755);
        options.open(&self.output_script)
            .and_then(|mut output| output.write_all(script.as_ref()))
            .chain_err(|| format!("failed to write output script '{}'", self.output_script))
    }
}

fn sh_quote<T: ToString>(s: &T) -> String {
    // We'll single-quote the whole thing, so first replace single-quotes with
    // '"'"' (leave quoting, double-quote one `'`, re-enter single-quoting)
    format!("'{}'", s.to_string().replace('\'', r#"'"'"'"#))
}
