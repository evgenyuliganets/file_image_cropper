use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

use super::naming;
use crate::error::{Error, Result};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CleanupReport {
    pub removed: u64,
    pub skipped: u64,
    pub failed: u64,
}

/// Removes only regular files whose names carry this package's ownership prefix.
pub fn cleanup_managed_files(
    directory: &Path,
    older_than: Option<Duration>,
) -> Result<CleanupReport> {
    if !directory.exists() {
        return Ok(CleanupReport::default());
    }
    if !directory.is_dir() {
        return Err(Error::InvalidManagedRoot(directory.to_path_buf()));
    }
    let mut report = CleanupReport::default();
    let now = SystemTime::now();
    let entries = fs::read_dir(directory)
        .map_err(|error| Error::io("read managed directory", directory, error))?;
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => {
                report.failed += 1;
                continue;
            }
        };
        let path = entry.path();
        let metadata = match entry.metadata() {
            Ok(metadata) => metadata,
            Err(_) => {
                report.failed += 1;
                continue;
            }
        };
        if !metadata.is_file() || !naming::is_owned_file(&path) {
            report.skipped += 1;
            continue;
        }
        if let Some(age) = older_than {
            let old_enough = metadata
                .modified()
                .ok()
                .and_then(|modified| now.duration_since(modified).ok())
                .is_some_and(|elapsed| elapsed >= age);
            if !old_enough {
                report.skipped += 1;
                continue;
            }
        }
        match fs::remove_file(&path) {
            Ok(()) => report.removed += 1,
            Err(_) => report.failed += 1,
        }
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn removes_only_owned_files() {
        let directory = crate::filesystem::staging::tests::temp_directory("cleanup");
        fs::write(directory.join("fic_output_owned.jpg"), b"owned").unwrap();
        fs::write(directory.join("unrelated.jpg"), b"keep").unwrap();
        fs::create_dir(directory.join("fic_directory")).unwrap();
        let report = cleanup_managed_files(&directory, None).unwrap();
        assert_eq!(
            report,
            CleanupReport {
                removed: 1,
                skipped: 2,
                failed: 0
            }
        );
        assert!(directory.join("unrelated.jpg").exists());
        fs::remove_dir_all(directory).unwrap();
    }
}
