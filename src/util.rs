use anyhow::{format_err, Context, Result};
use std::ffi::OsString;
use std::fs;
use std::ops::Deref;
use std::path::{Component, Path, PathBuf, Prefix};
use walkdir::WalkDir;

// Needed to set the script mode to executable.
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
// FIXME: what about Windows? Are default ACLs executable?

#[cfg(unix)]
use std::os::unix::fs::symlink as symlink_file;
#[cfg(windows)]
use std::os::windows::fs::symlink_file;

/// Converts a `&Path` to a UTF-8 `&str`.
pub fn path_to_str(path: &Path) -> Result<&str> {
    path.to_str().ok_or_else(|| format_err!("path is not valid UTF-8 '{}'", path.display()))
}

/// Wraps `fs::copy` with a nicer error message.
pub fn copy<P: AsRef<Path>, Q: AsRef<Path>>(from: P, to: Q) -> Result<u64> {
    if fs::symlink_metadata(&from)?.file_type().is_symlink() {
        let link = fs::read_link(&from)?;
        symlink_file(link, &to)?;
        Ok(0)
    } else {
        let amt = fs::copy(&from, &to).with_context(|| {
            format!(
                "failed to copy '{}' ({}) to '{}' ({}, parent {})",
                from.as_ref().display(),
                if from.as_ref().exists() { "exists" } else { "doesn't exist" },
                to.as_ref().display(),
                if to.as_ref().exists() { "exists" } else { "doesn't exist" },
                if to.as_ref().parent().unwrap_or_else(|| Path::new("")).exists() {
                    "exists"
                } else {
                    "doesn't exist"
                },
            )
        })?;
        Ok(amt)
    }
}

/// Wraps `fs::create_dir` with a nicer error message.
pub fn create_dir<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::create_dir(&path)
        .with_context(|| format!("failed to create dir '{}'", path.as_ref().display()))?;
    Ok(())
}

/// Wraps `fs::create_dir_all` with a nicer error message.
pub fn create_dir_all<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::create_dir_all(&path)
        .with_context(|| format!("failed to create dir '{}'", path.as_ref().display()))?;
    Ok(())
}

/// Wraps `fs::OpenOptions::create_new().open()` as executable, with a nicer error message.
pub fn create_new_executable<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o755);
    let file = options
        .open(&path)
        .with_context(|| format!("failed to create file '{}'", path.as_ref().display()))?;
    Ok(file)
}

/// Wraps `fs::OpenOptions::create_new().open()`, with a nicer error message.
pub fn create_new_file<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    let file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .with_context(|| format!("failed to create file '{}'", path.as_ref().display()))?;
    Ok(file)
}

/// Wraps `fs::File::open()` with a nicer error message.
pub fn open_file<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    let file = fs::File::open(&path)
        .with_context(|| format!("failed to open file '{}'", path.as_ref().display()))?;
    Ok(file)
}

/// Wraps `remove_dir_all` with a nicer error message.
pub fn remove_dir_all<P: AsRef<Path>>(path: P) -> Result<()> {
    remove_dir_all::remove_dir_all(path.as_ref())
        .with_context(|| format!("failed to remove dir '{}'", path.as_ref().display()))?;
    Ok(())
}

/// Wrap `fs::remove_file` with a nicer error message
pub fn remove_file<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::remove_file(path.as_ref())
        .with_context(|| format!("failed to remove file '{}'", path.as_ref().display()))?;
    Ok(())
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.
pub fn copy_recursive(src: &Path, dst: &Path) -> Result<()> {
    copy_with_callback(src, dst, |_, _| Ok(())).with_context(|| {
        format!(
            "failed to recursively copy '{}' ({}) to '{}' ({}, parent {})",
            src.display(),
            if src.exists() { "exists" } else { "doesn't exist" },
            dst.display(),
            if dst.exists() { "exists" } else { "doesn't exist" },
            if dst.parent().unwrap_or_else(|| Path::new("")).exists() {
                "exists"
            } else {
                "doesn't exist"
            },
        )
    })
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called. Invokes a callback for each path visited.
pub fn copy_with_callback<F>(src: &Path, dst: &Path, mut callback: F) -> Result<()>
where
    F: FnMut(&Path, fs::FileType) -> Result<()>,
{
    for entry in WalkDir::new(src).min_depth(1) {
        let entry = entry?;
        let file_type = entry.file_type();
        let path = entry.path().strip_prefix(src)?;
        let dst = dst.join(path);

        if file_type.is_dir() {
            create_dir(&dst)?;
        } else {
            copy(entry.path(), dst)?;
        }
        callback(&path, file_type)?;
    }
    Ok(())
}

fn normalize_rest(path: PathBuf) -> PathBuf {
    let mut new_components = vec![];
    for component in path.components().skip(1) {
        match component {
            Component::Prefix(_) => unreachable!(),
            Component::RootDir => new_components.clear(),
            Component::CurDir => {}
            Component::ParentDir => {
                new_components.pop();
            }
            Component::Normal(component) => new_components.push(component),
        }
    }
    new_components.into_iter().collect()
}

#[derive(Debug)]
pub struct LongPath(PathBuf);

impl LongPath {
    pub fn new(path: PathBuf) -> Self {
        let path = if cfg!(windows) {
            // Convert paths to verbatim paths to ensure that paths longer than 255 characters work
            match dbg!(path.components().next().unwrap()) {
                Component::Prefix(prefix_component) => {
                    match prefix_component.kind() {
                        Prefix::Verbatim(_)
                        | Prefix::VerbatimUNC(_, _)
                        | Prefix::VerbatimDisk(_) => {
                            // Already a verbatim path.
                            path
                        }

                        Prefix::DeviceNS(dev) => {
                            let mut base = OsString::from("\\\\?\\");
                            base.push(dev);
                            Path::new(&base).join(normalize_rest(path))
                        }
                        Prefix::UNC(host, share) => {
                            let mut base = OsString::from("\\\\?\\UNC\\");
                            base.push(host);
                            base.push("\\");
                            base.push(share);
                            Path::new(&base).join(normalize_rest(path))
                        }
                        Prefix::Disk(_disk) => {
                            let mut base = OsString::from("\\\\?\\");
                            base.push(prefix_component.as_os_str());
                            Path::new(&base).join(normalize_rest(path))
                        }
                    }
                }

                Component::RootDir
                | Component::CurDir
                | Component::ParentDir
                | Component::Normal(_) => {
                    return LongPath::new(dbg!(
                        std::env::current_dir().expect("failed to get current dir").join(&path)
                    ));
                }
            }
        } else {
            path
        };
        LongPath(dbg!(path))
    }
}

impl Into<LongPath> for &str {
    fn into(self) -> LongPath {
        LongPath::new(self.into())
    }
}

impl Deref for LongPath {
    type Target = Path;

    fn deref(&self) -> &Path {
        &self.0
    }
}

/// Creates an "actor" with default values and setters for all fields.
macro_rules! actor {
    ($( #[ $attr:meta ] )+ pub struct $name:ident {
        $( $( #[ $field_attr:meta ] )+ $field:ident : $type:ty = $default:expr, )*
    }) => {
        $( #[ $attr ] )+
        pub struct $name {
            $( $( #[ $field_attr ] )+ $field : $type, )*
        }

        impl Default for $name {
            fn default() -> Self {
                $name {
                    $( $field : $default.into(), )*
                }
            }
        }

        impl $name {
            $( $( #[ $field_attr ] )+
            pub fn $field(&mut self, value: $type) -> &mut Self {
                self.$field = value;
                self
            })+
        }
    }
}
