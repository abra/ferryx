//! Which shell a session runs, the environment it gets, and the line that
//! changes its folder.

use std::path::{Path, PathBuf};

use crate::error::{TermError, TermErrorKind};

/// The shell a session runs when the settings name none: the `SHELL`
/// variable, the user's login shell, then `/bin/zsh`, `/bin/bash`,
/// `/bin/sh`; PowerShell (`pwsh`, then Windows PowerShell), then `cmd` on
/// Windows.
pub fn default_shell() -> PathBuf {
    #[cfg(unix)]
    {
        let from_env = std::env::var_os("SHELL").map(PathBuf::from);
        from_env
            .into_iter()
            .chain(login_shell())
            .chain(["/bin/zsh", "/bin/bash", "/bin/sh"].map(PathBuf::from))
            .find(|p| p.is_absolute() && is_executable(p))
            .unwrap_or_else(|| PathBuf::from("/bin/sh"))
    }
    #[cfg(windows)]
    {
        find_on_path("pwsh.exe")
            .or_else(|| find_on_path("powershell.exe"))
            .or_else(|| std::env::var_os("COMSPEC").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("cmd.exe"))
    }
}

/// The shell for [`crate::SessionConfig::shell`]: the default when it is
/// empty, else the path or the name found on `PATH`, checked to be an
/// executable file so a typo is reported rather than silently replaced.
pub fn resolve_shell(choice: Option<&str>) -> Result<PathBuf, TermError> {
    let choice = choice.map(str::trim).filter(|c| !c.is_empty());
    let Some(choice) = choice else { return Ok(default_shell()) };
    let path = Path::new(choice);
    let has_separator = choice.contains('/') || (cfg!(windows) && choice.contains('\\'));
    let resolved = if has_separator {
        path.to_path_buf()
    } else {
        find_on_path(choice).ok_or_else(|| not_found(choice))?
    };
    if !resolved.exists() {
        return Err(not_found(choice));
    }
    if resolved.is_dir() || !is_executable(&resolved) {
        let path = resolved.to_string_lossy();
        return Err(TermError::new(TermErrorKind::PermissionDenied, path.clone()).with_path(path));
    }
    Ok(resolved)
}

/// The kind says what went wrong; the message is the shell as given, which
/// the interface shows under its own words for the kind.
fn not_found(choice: &str) -> TermError {
    TermError::new(TermErrorKind::NotFound, choice).with_path(choice)
}

fn find_on_path(name: &str) -> Option<PathBuf> {
    let paths = std::env::var_os("PATH")?;
    std::env::split_paths(&paths).map(|dir| dir.join(name)).find(|p| p.is_file() && is_executable(p))
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::ffi::OsStrExt;
    let Ok(c_path) = std::ffi::CString::new(path.as_os_str().as_bytes()) else { return false };
    // SAFETY: a valid NUL-terminated path; access(2) only reads it.
    unsafe { libc::access(c_path.as_ptr(), libc::X_OK) == 0 }
}

#[cfg(windows)]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

/// The shell of the user's account (passwd), which `SHELL` usually names.
#[cfg(unix)]
fn login_shell() -> Option<PathBuf> {
    use std::os::unix::ffi::OsStrExt;
    // SAFETY: getpwuid returns a pointer into static storage or null; the
    // shell string is copied before anything else can call it again.
    unsafe {
        let entry = libc::getpwuid(libc::getuid());
        if entry.is_null() || (*entry).pw_shell.is_null() {
            return None;
        }
        let shell = std::ffi::CStr::from_ptr((*entry).pw_shell);
        Some(PathBuf::from(std::ffi::OsStr::from_bytes(shell.to_bytes())))
    }
}

/// What a POSIX shell is typed to go to `folder`: ` cd -- 'folder'` and
/// Return. The leading space keeps it out of the history where the shell
/// honours that (`HISTCONTROL=ignorespace`, `setopt hist_ignore_space`).
/// `None` for a name with a control character: typed, a newline would end
/// the line in the middle.
pub fn cd_line(folder: &str) -> Option<String> {
    if folder.is_empty() || folder.chars().any(char::is_control) {
        return None;
    }
    Some(format!(" cd -- {}\r", quote(folder)))
}

/// `text` in single quotes, each quote inside closed, escaped and opened
/// again (`it's` → `'it'\''s'`): nothing in it is expanded.
pub fn quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

/// The `LANG` a shell gets when the environment names no locale (an app
/// started from the Dock has none, and a shell without one shows UTF-8 as
/// escapes): the system's language and region in UTF-8 when the system has
/// that locale, else US English, else `C.UTF-8`.
pub fn utf8_locale(preferred: Option<&str>, exists: impl Fn(&str) -> bool) -> String {
    let preferred = preferred
        .map(|p| p.split(['.', '@']).next().unwrap_or(p).replace('-', "_"))
        .filter(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'));
    preferred
        .map(|p| format!("{p}.UTF-8"))
        .into_iter()
        .chain(["en_US.UTF-8".to_string()])
        .find(|candidate| exists(candidate))
        .unwrap_or_else(|| "C.UTF-8".to_string())
}

/// Whether the system has the locale `name` (macOS keeps one folder per
/// locale; elsewhere the session's own `LANG` is normally set, and the
/// fallback is taken).
pub fn locale_exists(name: &str) -> bool {
    if cfg!(target_os = "macos") {
        Path::new("/usr/share/locale").join(name).is_dir()
    } else {
        false
    }
}

/// Whether the environment already names a locale for text.
pub fn has_locale(get: impl Fn(&str) -> Option<String>) -> bool {
    ["LC_ALL", "LC_CTYPE", "LANG"].iter().any(|key| get(key).is_some_and(|v| !v.is_empty()))
}

/// Variables another terminal set for its own sessions; a shell started
/// here (when Ferryx itself was launched from a terminal) must not see
/// them.
pub const FOREIGN_VARIABLES: &[&str] = &[
    "TERM_SESSION_ID",
    "ITERM_SESSION_ID",
    "ITERM_PROFILE",
    "TERMINAL_EMULATOR",
    "WT_SESSION",
    "WT_PROFILE_ID",
    "KITTY_WINDOW_ID",
    "ALACRITTY_WINDOW_ID",
    "VTE_VERSION",
    "COLUMNS",
    "LINES",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_closes_and_escapes_single_quotes() {
        assert_eq!(quote("/tmp/plain"), "'/tmp/plain'");
        assert_eq!(quote("/tmp/it's"), r"'/tmp/it'\''s'");
        assert_eq!(quote("/a b/$HOME/`x`/\"q\""), "'/a b/$HOME/`x`/\"q\"'");
    }

    #[test]
    fn cd_line_is_typed_with_a_leading_space_and_return() {
        assert_eq!(cd_line("/Users/me").as_deref(), Some(" cd -- '/Users/me'\r"));
        assert_eq!(cd_line("-rf").as_deref(), Some(" cd -- '-rf'\r"));
    }

    #[test]
    fn cd_line_refuses_control_characters() {
        assert_eq!(cd_line("/tmp/a\nrm -rf ~"), None);
        assert_eq!(cd_line("/tmp/tab\there"), None);
        assert_eq!(cd_line("/tmp/esc\u{1b}[2J"), None);
        assert_eq!(cd_line(""), None);
    }

    #[test]
    fn cd_line_keeps_unicode() {
        assert_eq!(cd_line("/tmp/Папка ✓").as_deref(), Some(" cd -- '/tmp/Папка ✓'\r"));
    }

    #[test]
    fn locale_prefers_the_system_language_when_present() {
        let have = |name: &str| ["ru_RU.UTF-8", "en_US.UTF-8"].contains(&name);
        assert_eq!(utf8_locale(Some("ru_RU"), have), "ru_RU.UTF-8");
        assert_eq!(utf8_locale(Some("ru-RU"), have), "ru_RU.UTF-8");
        assert_eq!(utf8_locale(Some("de_DE"), have), "en_US.UTF-8");
        assert_eq!(utf8_locale(None, have), "en_US.UTF-8");
        assert_eq!(utf8_locale(Some("de_DE"), |_| false), "C.UTF-8");
        // Nothing odd reaches the variable.
        assert_eq!(utf8_locale(Some("x/../y"), |_| true), "en_US.UTF-8");
    }

    #[test]
    fn has_locale_reads_the_three_variables() {
        assert!(!has_locale(|_| None));
        assert!(!has_locale(|_| Some(String::new())));
        assert!(has_locale(|k| (k == "LC_CTYPE").then(|| "UTF-8".to_string())));
    }

    #[cfg(unix)]
    #[test]
    fn resolve_shell_checks_the_choice() {
        assert_eq!(resolve_shell(None).unwrap(), default_shell());
        assert_eq!(resolve_shell(Some("  ")).unwrap(), default_shell());
        assert_eq!(resolve_shell(Some("/bin/sh")).unwrap(), PathBuf::from("/bin/sh"));
        assert!(resolve_shell(Some("sh")).unwrap().ends_with("sh"));
        let missing = resolve_shell(Some("/no/such/shell")).unwrap_err();
        assert_eq!(missing.kind, TermErrorKind::NotFound);
        assert_eq!(missing.path.as_deref(), Some("/no/such/shell"));
        assert_eq!(resolve_shell(Some("no-such-shell-here")).unwrap_err().kind, TermErrorKind::NotFound);
        let dir = tempfile::tempdir().unwrap();
        let plain = dir.path().join("plain");
        std::fs::write(&plain, "").unwrap();
        let denied = resolve_shell(Some(plain.to_str().unwrap())).unwrap_err();
        assert_eq!(denied.kind, TermErrorKind::PermissionDenied);
        assert_eq!(
            resolve_shell(Some(dir.path().to_str().unwrap())).unwrap_err().kind,
            TermErrorKind::PermissionDenied
        );
    }

    #[cfg(unix)]
    #[test]
    fn default_shell_is_an_executable() {
        let shell = default_shell();
        assert!(shell.is_absolute());
        assert!(is_executable(&shell));
    }
}
