use std::fs::{File, OpenOptions};
use std::path::Path;

use crate::error::{Error, Result};

/// Validates and opens an input file read-only, without copying or modifying it.
pub fn open_input(path: &Path) -> Result<File> {
    let metadata = match path.metadata() {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(Error::InputNotFound(path.to_path_buf()));
        }
        Err(error) => return Err(Error::io("inspect input", path, error)),
    };
    if !metadata.is_file() {
        return Err(Error::InputNotFile(path.to_path_buf()));
    }
    OpenOptions::new()
        .read(true)
        .open(path)
        .map_err(|error| Error::io("open input", path, error))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    #[test]
    fn opens_existing_input_read_only() {
        let directory = crate::filesystem::staging::tests::temp_directory("input");
        let path = directory.join("image.jpg");
        std::fs::write(&path, b"image").unwrap();
        let mut file = open_input(&path).unwrap();
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes).unwrap();
        assert_eq!(bytes, b"image");
        assert!(matches!(
            open_input(&directory),
            Err(Error::InputNotFile(_))
        ));
        std::fs::remove_dir_all(directory).unwrap();
    }
}
