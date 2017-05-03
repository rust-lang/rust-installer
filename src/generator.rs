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
use std::path::Path;
use walkdir::WalkDir;

use super::Scripter;
use super::Tarballer;

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
        fs::create_dir_all(&self.work_dir)?;

        let package_dir = Path::new(&self.work_dir).join(&self.package_name);
        if package_dir.exists() {
            fs::remove_dir_all(&package_dir)?;
        }

        // Copy the image and write the manifest
        let component_dir = package_dir.join(&self.component_name);
        fs::create_dir_all(&component_dir)?;
        copy_and_manifest(self.image_dir.as_ref(), &component_dir, &self.bulk_dirs)?;

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
            copy_recursive(self.non_installed_overlay.as_ref(), &package_dir)?;
        }

        // Generate the install script
        let output_script = package_dir.join("install.sh");
        let mut scripter = Scripter::default();
        scripter.product_name(self.product_name)
            .rel_manifest_dir(self.rel_manifest_dir)
            .success_message(self.success_message)
            .legacy_manifest_dirs(self.legacy_manifest_dirs)
            .output_script(output_script.to_str().unwrap().into());
        scripter.run()?;

        // Make the tarballs
        fs::create_dir_all(&self.output_dir)?;
        let output = Path::new(&self.output_dir).join(&self.package_name);
        let mut tarballer = Tarballer::default();
        tarballer.work_dir(self.work_dir)
            .input(self.package_name)
            .output(output.to_str().unwrap().into());
        tarballer.run()?;

        Ok(())
    }
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.
fn copy_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    copy_with_callback(src, dst, |_, _| Ok(()))
}

/// Copies the `src` directory recursively to `dst`, writing `manifest.in` too.
fn copy_and_manifest(src: &Path, dst: &Path, bulk_dirs: &str) -> io::Result<()> {
    let manifest = fs::File::create(dst.join("manifest.in"))?;
    let bulk_dirs: Vec<_> = bulk_dirs.split(',')
        .filter(|s| !s.is_empty())
        .map(Path::new).collect();

    copy_with_callback(src, dst, |path, file_type| {
        if file_type.is_dir() {
            if bulk_dirs.contains(&path) {
                writeln!(&manifest, "dir:{}", path.display())?;
            }
        } else {
            if !bulk_dirs.iter().any(|d| path.starts_with(d)) {
                writeln!(&manifest, "file:{}", path.display())?;
            }
        }
        Ok(())
    })
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.  Invokes a callback for each path visited.
fn copy_with_callback<F>(src: &Path, dst: &Path, mut callback: F) -> io::Result<()>
    where F: FnMut(&Path, fs::FileType) -> io::Result<()>
{
    for entry in WalkDir::new(src).min_depth(1) {
        let entry = entry?;
        let file_type = entry.file_type();
        let path = entry.path().strip_prefix(src).unwrap();
        let dst = dst.join(path);

        if file_type.is_dir() {
            fs::create_dir(&dst)?;
        } else {
            fs::copy(entry.path(), dst)?;
        }
        callback(&path, file_type)?;
    }
    Ok(())
}
