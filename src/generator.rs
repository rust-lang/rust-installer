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
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug)]
pub struct Generator {
    product_name: String,
    component_name: String,
    package_name: String,
    rel_manifest_dir: String,
    success_message: String,
    legacy_manifest_dirs: String,
    non_installed_overlay: String,
    bulk_dirs: String,
    image_dir: String,
    work_dir: String,
    output_dir: String,
}

impl Default for Generator {
    fn default() -> Generator {
        Generator {
            product_name: "Product".into(),
            component_name: "component".into(),
            package_name: "package".into(),
            rel_manifest_dir: "packagelib".into(),
            success_message: "Installed.".into(),
            legacy_manifest_dirs: "".into(),
            non_installed_overlay: "".into(),
            bulk_dirs: "".into(),
            image_dir: "./install_image".into(),
            work_dir: "./workdir".into(),
            output_dir: "./dist".into(),
        }
    }
}

impl Generator {
    /// The name of the product, for display
    pub fn product_name(&mut self, value: String) -> &mut Self {
        self.product_name = value;
        self
    }

    /// The name of the component, distinct from other installed components
    pub fn component_name(&mut self, value: String) -> &mut Self {
        self.component_name = value;
        self
    }

    /// The name of the package, tarball
    pub fn package_name(&mut self, value: String) -> &mut Self {
        self.package_name = value;
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

    /// Directory containing files that should not be installed
    pub fn non_installed_overlay(&mut self, value: String) -> &mut Self {
        self.non_installed_overlay = value;
        self
    }

    /// Path prefixes of directories that should be installed/uninstalled in bulk
    pub fn bulk_dirs(&mut self, value: String) -> &mut Self {
        self.bulk_dirs = value;
        self
    }

    /// The directory containing the installation medium
    pub fn image_dir(&mut self, value: String) -> &mut Self {
        self.image_dir = value;
        self
    }

    /// The directory to do temporary work
    pub fn work_dir(&mut self, value: String) -> &mut Self {
        self.work_dir = value;
        self
    }

    /// The location to put the final image and tarball
    pub fn output_dir(&mut self, value: String) -> &mut Self {
        self.output_dir = value;
        self
    }

    /// Generate the actual installer tarball
    pub fn run(self) -> io::Result<()> {
        let src_dir = Path::new(::SOURCE_DIRECTORY);
        fs::read_dir(&src_dir)?;

        fs::create_dir_all(&self.work_dir)?;

        let package_dir = Path::new(&self.work_dir).join(&self.package_name);
        if package_dir.exists() {
            fs::remove_dir_all(&package_dir)?;
        }

        let component_dir = package_dir.join(&self.component_name);
        fs::create_dir_all(&component_dir)?;
        let mut files = cp_r(self.image_dir.as_ref(), &component_dir)?;

        // Filter out files that are covered by bulk dirs.
        let bulk_dirs: Vec<_> = self.bulk_dirs.split(',').filter(|s| !s.is_empty()).collect();
        files.retain(|f| !bulk_dirs.iter().any(|d| f.starts_with(d)));

        // Write the manifest
        let manifest = fs::File::create(component_dir.join("manifest.in"))?;
        for file in files {
            writeln!(&manifest, "file:{}", file.display())?;
        }
        for dir in bulk_dirs {
            writeln!(&manifest, "dir:{}", dir)?;
        }
        drop(manifest);

        // Write the component name
        let components = fs::File::create(package_dir.join("components"))?;
        writeln!(&components, "{}", self.component_name)?;
        drop(components);

        // Write the installer version (only used by combine-installers.sh)
        let version = fs::File::create(package_dir.join("rust-installer-version"))?;
        writeln!(&version, "{}", ::RUST_INSTALLER_VERSION)?;
        drop(version);

        // Copy the overlay
        if !self.non_installed_overlay.is_empty() {
            cp_r(self.non_installed_overlay.as_ref(), &package_dir)?;
        }

        // Generate the install script (TODO: run this in-process!)
        let output_script = package_dir.join("install.sh");
        let status = Command::new(src_dir.join("gen-install-script.sh"))
            .arg(format!("--product-name={}", self.product_name))
            .arg(format!("--rel-manifest-dir={}", self.rel_manifest_dir))
            .arg(format!("--success-message={}", self.success_message))
            .arg(format!("--legacy-manifest-dirs={}", self.legacy_manifest_dirs))
            .arg(format!("--output-script={}", output_script.display()))
            .status()?;
        if !status.success() {
            let msg = format!("failed to generate install script: {}", status);
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }

        // Make the tarballs (TODO: run this in-process!)
        fs::create_dir_all(&self.output_dir)?;
        let output = Path::new(&self.output_dir).join(&self.package_name);
        let status = Command::new(src_dir.join("make-tarballs.sh"))
            .arg(format!("--work-dir={}", self.work_dir))
            .arg(format!("--input={}", self.package_name))
            .arg(format!("--output={}", output.display()))
            .status()?;
        if !status.success() {
            let msg = format!("failed to make tarballs: {}", status);
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }

        Ok(())
    }
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called. Returns a list of files written relative to `dst`.
pub fn cp_r(src: &Path, dst: &Path) -> io::Result<Vec<PathBuf>> {
    let mut files = vec![];
    for f in fs::read_dir(src)? {
        let f = f?;
        let path = f.path();
        let name = PathBuf::from(f.file_name());
        let dst = dst.join(&name);
        if f.file_type()?.is_dir() {
            fs::create_dir(&dst)?;
            let subfiles = cp_r(&path, &dst)?;
            files.extend(subfiles.into_iter().map(|f| name.join(f)));
        } else {
            fs::copy(&path, &dst)?;
            files.push(name);
        }
    }
    Ok(files)
}
