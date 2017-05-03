#[macro_use]
extern crate clap;
extern crate installer;

use clap::{App, ArgMatches};
use installer::*;

fn main() {
    let yaml = load_yaml!("main.yml");
    let matches = App::from_yaml(yaml).get_matches();

    match matches.subcommand() {
        ("generate", Some(matches)) => generate(matches),
        ("script", Some(matches)) => script(matches),
        _ => unreachable!(),
    }
}

fn generate(matches: &ArgMatches) {
    let mut gen = Generator::default();
    matches
        .value_of("product-name")
        .map(|s| gen.product_name(s.into()));
    matches
        .value_of("component-name")
        .map(|s| gen.component_name(s.into()));
    matches
        .value_of("package-name")
        .map(|s| gen.package_name(s.into()));
    matches
        .value_of("rel-manifest-dir")
        .map(|s| gen.rel_manifest_dir(s.into()));
    matches
        .value_of("success-message")
        .map(|s| gen.success_message(s.into()));
    matches
        .value_of("legacy-manifest-dirs")
        .map(|s| gen.legacy_manifest_dirs(s.into()));
    matches
        .value_of("non-installed-overlay")
        .map(|s| gen.non_installed_overlay(s.into()));
    matches
        .value_of("bulk-dirs")
        .map(|s| gen.bulk_dirs(s.into()));
    matches
        .value_of("image-dir")
        .map(|s| gen.image_dir(s.into()));
    matches
        .value_of("work-dir")
        .map(|s| gen.work_dir(s.into()));
    matches
        .value_of("output-dir")
        .map(|s| gen.output_dir(s.into()));

    if let Err(e) = gen.run() {
        println!("failed to generate installer: {}", e);
        std::process::exit(1);
    }
}

fn script(matches: &ArgMatches) {
    let mut scr = Scripter::default();
    matches
        .value_of("product-name")
        .map(|s| scr.product_name(s.into()));
    matches
        .value_of("rel-manifest-dir")
        .map(|s| scr.rel_manifest_dir(s.into()));
    matches
        .value_of("success-message")
        .map(|s| scr.success_message(s.into()));
    matches
        .value_of("legacy-manifest-dirs")
        .map(|s| scr.legacy_manifest_dirs(s.into()));
    matches
        .value_of("output-script")
        .map(|s| scr.output_script(s.into()));

    if let Err(e) = scr.run() {
        println!("failed to generate installation script: {}", e);
        std::process::exit(1);
    }
}
