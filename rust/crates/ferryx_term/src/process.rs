//! What the system tells about the shell: its current folder.
//!
//! Whether it waits at its prompt comes from the pseudo-terminal's
//! foreground process group (`tcgetpgrp` on the master, which
//! `MasterPty::process_group_leader` wraps): a shell with job control puts
//! itself in front while it reads a line and the program it runs while
//! that runs.
//!
//! Windows has neither: ConPTY names no foreground process, and another
//! process's folder lives in its PEB, readable only with
//! `NtQueryInformationProcess` and `ReadProcessMemory`. A session there
//! reports both as unknown, and the folder is never synchronised.

use std::path::PathBuf;

/// The current folder of process `pid`: `proc_pidinfo` on macOS, the
/// `/proc/<pid>/cwd` link on Linux; `None` elsewhere or when the process
/// is gone.
pub fn folder_of(pid: u32) -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        macos_folder(pid)
    }
    #[cfg(target_os = "linux")]
    {
        std::fs::read_link(format!("/proc/{pid}/cwd")).ok()
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        let _ = pid;
        None
    }
}

#[cfg(target_os = "macos")]
fn macos_folder(pid: u32) -> Option<PathBuf> {
    use std::os::unix::ffi::OsStrExt;
    let pid = libc::c_int::try_from(pid).ok()?;
    // SAFETY: an all-zero proc_vnodepathinfo is valid; proc_pidinfo writes
    // at most `size` bytes into it and answers how many it wrote.
    let mut info: libc::proc_vnodepathinfo = unsafe { std::mem::zeroed() };
    let size = std::mem::size_of::<libc::proc_vnodepathinfo>() as libc::c_int;
    let written = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDVNODEPATHINFO,
            0,
            (&mut info as *mut libc::proc_vnodepathinfo).cast(),
            size,
        )
    };
    if written != size {
        return None;
    }
    // The path is a NUL-terminated MAXPATHLEN buffer kept as 32 × 32 bytes.
    let raw = &info.pvi_cdir.vip_path;
    // SAFETY: the 2D array is contiguous `c_char`s, 1024 in all.
    let bytes: &[u8] =
        unsafe { std::slice::from_raw_parts(raw.as_ptr().cast::<u8>(), std::mem::size_of_val(raw)) };
    let end = bytes.iter().position(|&b| b == 0)?;
    (end > 0).then(|| PathBuf::from(std::ffi::OsStr::from_bytes(&bytes[..end])))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn reads_this_process_folder() {
        let folder = folder_of(std::process::id()).expect("own folder");
        assert_eq!(folder.canonicalize().unwrap(), std::env::current_dir().unwrap().canonicalize().unwrap());
    }

    #[test]
    fn a_missing_process_has_none() {
        // Far above any pid the systems hand out.
        assert_eq!(folder_of(999_999_999), None);
    }
}
