use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::PathBuf;

#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos"
))]
use std::ffi::CString;
#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos"
))]
use std::os::unix::ffi::OsStrExt;

use super::{OutputTarget, naming};
use crate::error::{Error, Result};

pub struct StagedOutput {
    file: Option<File>,
    staging_path: PathBuf,
    target: OutputTarget,
    committed: bool,
}

impl StagedOutput {
    pub fn create(target: OutputTarget) -> Result<Self> {
        for _ in 0..32 {
            let staging_path = naming::staging_path(target.path());
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&staging_path)
            {
                Ok(file) => {
                    return Ok(Self {
                        file: Some(file),
                        staging_path,
                        target,
                        committed: false,
                    });
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(Error::io("create staging output", staging_path, error)),
            }
        }
        Err(Error::io(
            "create unique staging output",
            target.path(),
            io::Error::new(
                io::ErrorKind::AlreadyExists,
                "unique name attempts exhausted",
            ),
        ))
    }

    pub fn writer(&mut self) -> &mut File {
        self.file
            .as_mut()
            .expect("writer is unavailable after commit")
    }

    pub fn commit(mut self) -> Result<PathBuf> {
        let mut file = self.file.take().expect("commit called once");
        file.flush()
            .map_err(|error| Error::io("flush staging output", &self.staging_path, error))?;
        file.sync_all()
            .map_err(|error| Error::io("sync staging output", &self.staging_path, error))?;
        drop(file);
        if self.target.overwrite() {
            if self.target.path().exists() {
                fs::remove_file(self.target.path()).map_err(|error| {
                    Error::io("replace existing output", self.target.path(), error)
                })?;
            }
            fs::rename(&self.staging_path, self.target.path())
                .map_err(|error| Error::io("commit staging output", &self.staging_path, error))?;
        } else {
            match commit_without_overwrite(&self.staging_path, self.target.path()) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                    return Err(Error::OutputExists(self.target.path().to_path_buf()));
                }
                Err(error) => {
                    return Err(Error::io(
                        "commit output without overwrite",
                        self.target.path(),
                        error,
                    ));
                }
            }
        }
        self.committed = true;
        Ok(self.target.path().to_path_buf())
    }
}

#[cfg(any(target_os = "android", target_os = "linux"))]
fn commit_without_overwrite(staging: &std::path::Path, target: &std::path::Path) -> io::Result<()> {
    let staging = CString::new(staging.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "staging path contains NUL"))?;
    let target = CString::new(target.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "output path contains NUL"))?;
    // SAFETY: Both C strings remain alive for the call and contain no interior
    // NUL bytes. RENAME_NOREPLACE atomically fails when `target` exists.
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            staging.as_ptr(),
            libc::AT_FDCWD,
            target.as_ptr(),
            libc::RENAME_NOREPLACE as libc::c_uint,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn commit_without_overwrite(staging: &std::path::Path, target: &std::path::Path) -> io::Result<()> {
    let staging = CString::new(staging.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "staging path contains NUL"))?;
    let target = CString::new(target.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "output path contains NUL"))?;
    // SAFETY: Both C strings remain alive for the call and contain no interior
    // NUL bytes. RENAME_EXCL atomically fails when `target` exists.
    let result = unsafe { libc::renamex_np(staging.as_ptr(), target.as_ptr(), libc::RENAME_EXCL) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos"
)))]
fn commit_without_overwrite(staging: &std::path::Path, target: &std::path::Path) -> io::Result<()> {
    fs::hard_link(staging, target)?;
    fs::remove_file(staging)
}

impl Drop for StagedOutput {
    fn drop(&mut self) {
        if !self.committed {
            let _ = fs::remove_file(&self.staging_path);
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    pub(crate) fn temp_directory(label: &str) -> PathBuf {
        let token = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "file_image_cropper_test_{label}_{}_{token}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        path
    }

    #[test]
    fn commits_complete_file() {
        let directory = temp_directory("commit");
        let target = OutputTarget::explicit(directory.join("result.jpg"), false).unwrap();
        let mut staged = StagedOutput::create(target).unwrap();
        staged.writer().write_all(b"complete").unwrap();
        let path = staged.commit().unwrap();
        assert_eq!(fs::read(path).unwrap(), b"complete");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn does_not_overwrite_output_created_after_validation() {
        let directory = temp_directory("no_overwrite");
        let path = directory.join("result.png");
        let target = OutputTarget::explicit(&path, false).unwrap();
        let mut staged = StagedOutput::create(target).unwrap();
        staged.writer().write_all(b"new").unwrap();
        fs::write(&path, b"existing").unwrap();
        assert!(matches!(staged.commit(), Err(Error::OutputExists(_))));
        assert_eq!(fs::read(&path).unwrap(), b"existing");
        fs::remove_dir_all(directory).unwrap();
    }
}
