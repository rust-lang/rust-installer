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
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::Command;

use super::Scripter;
use super::Tarballer;
use util::*;

#[derive(Debug)]
pub struct Combiner {
    product_name: String,
    package_name: String,
    rel_manifest_dir: String,
    success_message: String,
    legacy_manifest_dirs: String,
    input_tarballs: String,
    non_installed_overlay: String,
    work_dir: String,
    output_dir: String,
}

impl Default for Combiner {
    fn default() -> Combiner {
        Combiner {
            product_name: "Product".into(),
            package_name: "package".into(),
            rel_manifest_dir: "packagelib".into(),
            success_message: "Installed.".into(),
            legacy_manifest_dirs: "".into(),
            input_tarballs: "".into(),
            non_installed_overlay: "".into(),
            work_dir: "./workdir".into(),
            output_dir: "./dist".into(),
        }
    }
}

impl Combiner {
    /// The name of the product, for display
    pub fn product_name(&mut self, value: String) -> &mut Self {
        self.product_name = value;
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

    /// Installers to combine
    pub fn input_tarballs(&mut self, value: String) -> &mut Self {
        self.input_tarballs = value;
        self
    }

    /// Directory containing files that should not be installed
    pub fn non_installed_overlay(&mut self, value: String) -> &mut Self {
        self.non_installed_overlay = value;
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
        let path = get_path()?;
        need_cmd(&path, "tar")?;

        fs::create_dir_all(&self.work_dir)?;

        let package_dir = Path::new(&self.work_dir).join(&self.package_name);
        if package_dir.exists() {
            fs::remove_dir_all(&package_dir)?;
        }
        fs::create_dir_all(&package_dir)?;

        // Merge each installer into the work directory of the new installer
        let components = fs::File::create(package_dir.join("components"))?;
        for input_tarball in self.input_tarballs.split(',').map(str::trim).filter(|s| !s.is_empty()) {
            // Extract the input tarballs
            let status = Command::new("tar")
                .arg("xzf")
                .arg(&input_tarball)
                .arg("-C")
                .arg(&self.work_dir)
                .status()?;
            if !status.success() {
                let msg = format!("failed to extract tarball: {}", status);
                return Err(io::Error::new(io::ErrorKind::Other, msg));
            }

            let pkg_name = input_tarball.trim_right_matches(".tar.gz");
            let pkg_name = Path::new(pkg_name).file_name().unwrap();
            let pkg_dir = Path::new(&self.work_dir).join(&pkg_name);

            // Verify the version number
            let mut version = String::new();
            fs::File::open(pkg_dir.join("rust-installer-version"))?
                .read_to_string(&mut version)?;
            if version.trim().parse() != Ok(::RUST_INSTALLER_VERSION) {
                let msg = format!("incorrect installer version in {}", input_tarball);
                return Err(io::Error::new(io::ErrorKind::Other, msg));
            }

            // Copy components to new combined installer
            let mut pkg_components = String::new();
            fs::File::open(pkg_dir.join("components"))?
                .read_to_string(&mut pkg_components)?;
            for component in pkg_components.split_whitespace() {
                // All we need to do is copy the component directory
                let component_dir = package_dir.join(&component);
                fs::create_dir(&component_dir)?;
                copy_recursive(&pkg_dir.join(&component), &component_dir)?;

                // Merge the component name
                writeln!(&components, "{}", component)?;
            }
        }
        drop(components);

        // Write the installer version
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
