#[macro_use]
extern crate clap;
extern crate installer;

use clap::{App, ArgMatches};
use installer::*;

fn main() {
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

fn combine(matches: &ArgMatches) {
    let combiner = parse!(matches => Combiner {
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

    if let Err(e) = combiner.run() {
        println!("failed to combine installers: {}", e);
        std::process::exit(1);
    }
}

fn generate(matches: &ArgMatches) {
    let generator = parse!(matches => Generator {
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

    if let Err(e) = generator.run() {
        println!("failed to generate installer: {}", e);
        std::process::exit(1);
    }
}

fn script(matches: &ArgMatches) {
    let scripter = parse!(matches => Scripter {
        "product-name" => product_name,
        "rel-manifest-dir" => rel_manifest_dir,
        "success-message" => success_message,
        "legacy-manifest-dirs" => legacy_manifest_dirs,
        "output-script" => output_script,
    });

    if let Err(e) = scripter.run() {
        println!("failed to generate installation script: {}", e);
        std::process::exit(1);
    }
}

fn tarball(matches: &ArgMatches) {
    let tarballer = parse!(matches => Tarballer {
        "input" => input,
        "output" => output,
        "work-dir" => work_dir,
    });

    if let Err(e) = tarballer.run() {
        println!("failed to generate tarballs: {}", e);
        std::process::exit(1);
    }
}
