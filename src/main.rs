#[macro_use]
extern crate clap;
#[macro_use]
extern crate error_chain;
use installer;

use crate::errors::*;
use clap::{App, ArgMatches};

mod errors {
    error_chain!{
        links {
            Installer(::installer::Error, ::installer::ErrorKind);
        }
    }
}

quick_main!(run);

fn run() -> Result<()> {
    let yaml = load_yaml!("main.yml");
    let matches = App::from_yaml(yaml).get_matches();

    match matches.subcommand() {
        ("combine", Some(matches)) => combine(matches),
        ("generate", Some(matches)) => generate(matches),
        ("script", Some(matches)) => script(matches),
        ("tarball", Some(matches)) => tarball(matches),
        _ => unreachable!(),
    }
}

/// Parse clap arguements into the type constructor.
macro_rules! parse(
    ($matches:expr => $type:ty { $( $option:tt => $setter:ident, )* }) => {
        {
            let mut command: $type = Default::default();
            $( $matches.value_of($option).map(|s| command.$setter(s)); )*
            command
        }
    }
);

fn combine(matches: &ArgMatches<'_>) -> Result<()> {
    let combiner = parse!(matches => installer::Combiner {
        "product-name" => product_name,
        "package-name" => package_name,
        "rel-manifest-dir" => rel_manifest_dir,
        "success-message" => success_message,
        "legacy-manifest-dirs" => legacy_manifest_dirs,
        "input-tarballs" => input_tarballs,
        "non-installed-overlay" => non_installed_overlay,
        "work-dir" => work_dir,
        "output-dir" => output_dir,
    });

    combiner.run().chain_err(|| "failed to combine installers")
}

fn generate(matches: &ArgMatches<'_>) -> Result<()> {
    let generator = parse!(matches => installer::Generator {
        "product-name" => product_name,
        "component-name" => component_name,
        "package-name" => package_name,
        "rel-manifest-dir" => rel_manifest_dir,
        "success-message" => success_message,
        "legacy-manifest-dirs" => legacy_manifest_dirs,
        "non-installed-overlay" => non_installed_overlay,
        "bulk-dirs" => bulk_dirs,
        "image-dir" => image_dir,
        "work-dir" => work_dir,
        "output-dir" => output_dir,
    });

    generator.run().chain_err(|| "failed to generate installer")
}

fn script(matches: &ArgMatches<'_>) -> Result<()> {
    let scripter = parse!(matches => installer::Scripter {
        "product-name" => product_name,
        "rel-manifest-dir" => rel_manifest_dir,
        "success-message" => success_message,
        "legacy-manifest-dirs" => legacy_manifest_dirs,
        "output-script" => output_script,
    });

    scripter.run().chain_err(|| "failed to generate installation script")
}

fn tarball(matches: &ArgMatches<'_>) -> Result<()> {
    let tarballer = parse!(matches => installer::Tarballer {
        "input" => input,
        "output" => output,
        "work-dir" => work_dir,
    });

    tarballer.run().chain_err(|| "failed to generate tarballs")
}
