use std::fs;
use std::path::{Path, PathBuf};

use super::naming;
use crate::error::{Error, Result};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OutputFileType {
    Jpeg,
    Png,
    WebP,
}

impl OutputFileType {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Jpeg => "jpg",
            Self::Png => "png",
            Self::WebP => "webp",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OutputTarget {
    final_path: PathBuf,
    managed: bool,
    overwrite: bool,
}

impl OutputTarget {
    pub fn explicit(path: impl Into<PathBuf>, overwrite: bool) -> Result<Self> {
        let path = path.into();
        validate_parent(&path)?;
        if !overwrite && path.exists() {
            return Err(Error::OutputExists(path));
        }
        Ok(Self {
            final_path: path,
            managed: false,
            overwrite,
        })
    }

    pub fn managed(root: &Path, file_type: OutputFileType) -> Result<Self> {
        if root.exists() && !root.is_dir() {
            return Err(Error::InvalidManagedRoot(root.to_path_buf()));
        }
        fs::create_dir_all(root)
            .map_err(|error| Error::io("create managed output directory", root, error))?;
        Ok(Self {
            final_path: naming::managed_path(root, file_type.extension()),
            managed: true,
            overwrite: false,
        })
    }

    pub fn path(&self) -> &Path {
        &self.final_path
    }
    pub fn is_managed(&self) -> bool {
        self.managed
    }
    pub fn overwrite(&self) -> bool {
        self.overwrite
    }
}

fn validate_parent(path: &Path) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    if !parent.exists() {
        return Err(Error::OutputParentMissing(parent.to_path_buf()));
    }
    if !parent.is_dir() {
        return Err(Error::OutputParentNotDirectory(parent.to_path_buf()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn creates_managed_output_name_and_directory() {
        let base = crate::filesystem::staging::tests::temp_directory("managed_base");
        let root = base.join("file_image_cropper");
        let target = OutputTarget::managed(&root, OutputFileType::Png).unwrap();
        assert!(root.is_dir());
        assert!(target.is_managed());
        assert_eq!(target.path().extension().unwrap(), "png");
        assert!(super::naming::is_owned_file(target.path()));
        std::fs::remove_dir_all(base).unwrap();
    }
}
