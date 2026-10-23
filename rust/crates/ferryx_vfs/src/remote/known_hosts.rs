//! SSH host keys as OpenSSH records them: the user's `~/.ssh/known_hosts`
//! (and `known_hosts2`), the system's `/etc/ssh/ssh_known_hosts`, read
//! only; and Ferryx's own file, where the keys the user accepts go. A key
//! on record lets the connection go on; a different key of the same type
//! for the host stops it (a changed key may be an attack, and no click
//! overrides it); a key the files do not know is shown to the user.
//!
//! Lines are read as OpenSSH reads them: host patterns with `*`, `?` and
//! `!`, `[host]:port` for another port, hashed hosts (`|1|salt|hash`),
//! `@revoked` keys refused, `@cert-authority` lines left aside.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use hmac::{Hmac, Mac};
use parking_lot::RwLock;
use russh::keys::{Algorithm, HashAlg, PublicKey};
use sha1::Sha1;

use crate::error::{IoAt, VfsResult};

/// What the files say of a host's key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HostKeyCheck {
    /// The key is on record for the host.
    Known,
    /// No key of this type is on record for the host.
    Unknown,
    /// Another key of this type is on record: the key changed.
    Changed { file: PathBuf, line: usize },
    /// The key is marked `@revoked`.
    Revoked { file: PathBuf, line: usize },
}

struct Files {
    /// Read only: the user's and the system's.
    read: Vec<PathBuf>,
    /// Read and appended to: Ferryx's own.
    own: PathBuf,
}

static FILES: LazyLock<RwLock<Files>> = LazyLock::new(|| RwLock::new(default_files()));

fn default_files() -> Files {
    let home = crate::system::home_dir();
    let mut read = vec![home.join(".ssh/known_hosts"), home.join(".ssh/known_hosts2")];
    if cfg!(unix) {
        read.push(PathBuf::from("/etc/ssh/ssh_known_hosts"));
    }
    Files { read, own: own_file(&home) }
}

/// Where Ferryx keeps the keys the user accepted: beside its other
/// settings on each desktop.
fn own_file(home: &Path) -> PathBuf {
    if cfg!(target_os = "macos") {
        home.join("Library/Application Support/Ferryx/known_hosts")
    } else if cfg!(windows) {
        std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join("AppData/Roaming"))
            .join("Ferryx/known_hosts")
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".config"))
            .join("ferryx/known_hosts")
    }
}

/// Reads `read` and `own` instead of the user's files (the tests).
pub fn use_files(read: Vec<PathBuf>, own: PathBuf) {
    *FILES.write() = Files { read, own };
}

/// Ferryx's own file.
pub fn own_path() -> PathBuf {
    FILES.read().own.clone()
}

/// What the files say of `key` for `host` on `port`.
pub fn check(host: &str, port: u16, key: &PublicKey) -> HostKeyCheck {
    let files = FILES.read();
    let paths: Vec<&PathBuf> = files.read.iter().chain(std::iter::once(&files.own)).collect();
    let target = host_port(host, port);
    let mut known = false;
    let mut changed = None;
    for path in paths {
        let Ok(text) = fs::read_to_string(path) else { continue };
        for (number, line) in text.lines().enumerate() {
            let Some(record) = Record::parse(line) else { continue };
            if !record.matches(&target) {
                continue;
            }
            let Ok(recorded) = russh::keys::parse_public_key_base64(record.key) else { continue };
            let same_key = recorded.key_data() == key.key_data();
            match record.marker {
                Marker::Revoked if same_key => {
                    return HostKeyCheck::Revoked { file: path.clone(), line: number + 1 };
                }
                Marker::Revoked | Marker::CertAuthority => {}
                Marker::None if same_key => known = true,
                Marker::None => {
                    if changed.is_none() && key_type(&recorded) == key_type(key) {
                        changed = Some(HostKeyCheck::Changed { file: path.clone(), line: number + 1 });
                    }
                }
            }
        }
    }
    if known {
        HostKeyCheck::Known
    } else {
        changed.unwrap_or(HostKeyCheck::Unknown)
    }
}

/// Adds `key` for `host` on `port` to Ferryx's own file.
pub fn remember(host: &str, port: u16, key: &PublicKey) -> VfsResult<()> {
    let path = own_path();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).at(dir)?;
    }
    let mut file = OpenOptions::new().create(true).append(true).open(&path).at(&path)?;
    let text =
        key.to_openssh().map_err(|e| crate::VfsError::new(crate::VfsErrorKind::Io, None, e.to_string()))?;
    // The comment a key may carry is the server's, not ours.
    let mut parts = text.split_whitespace();
    let (kind, data) = (parts.next().unwrap_or_default(), parts.next().unwrap_or_default());
    writeln!(file, "{} {kind} {data}", host_port(host, port)).at(&path)
}

/// The key's fingerprint as OpenSSH prints it: `SHA256:` and the hash in
/// Base64 without padding.
pub fn fingerprint(key: &PublicKey) -> String {
    key.fingerprint(HashAlg::Sha256).to_string()
}

/// The key's type as known_hosts files name it (`ssh-rsa` whatever hash
/// signs with it).
pub fn key_type(key: &PublicKey) -> String {
    match key.algorithm() {
        Algorithm::Rsa { .. } => "ssh-rsa".to_string(),
        other => other.as_str().to_string(),
    }
}

/// How a host is named in the files: `host`, or `[host]:port` off port 22.
fn host_port(host: &str, port: u16) -> String {
    if port == 22 {
        host.to_ascii_lowercase()
    } else {
        format!("[{}]:{port}", host.to_ascii_lowercase())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Marker {
    None,
    Revoked,
    CertAuthority,
}

struct Record<'a> {
    marker: Marker,
    hosts: &'a str,
    key: &'a str,
}

impl<'a> Record<'a> {
    fn parse(line: &'a str) -> Option<Record<'a>> {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            return None;
        }
        let mut tokens = line.split_whitespace();
        let mut first = tokens.next()?;
        let marker = match first {
            "@revoked" => Marker::Revoked,
            "@cert-authority" => Marker::CertAuthority,
            other if other.starts_with('@') => return None,
            _ => Marker::None,
        };
        if marker != Marker::None {
            first = tokens.next()?;
        }
        let _kind = tokens.next()?;
        let key = tokens.next()?;
        Some(Record { marker, hosts: first, key })
    }

    /// Whether the line's patterns take `target` in: one matches and no
    /// negated one does.
    fn matches(&self, target: &str) -> bool {
        let mut matched = false;
        for pattern in self.hosts.split(',') {
            if let Some(negated) = pattern.strip_prefix('!') {
                if glob(&negated.to_ascii_lowercase(), target) {
                    return false;
                }
            } else if let Some(hashed) = pattern.strip_prefix("|1|") {
                matched |= hashed_matches(hashed, target);
            } else {
                matched |= glob(&pattern.to_ascii_lowercase(), target);
            }
        }
        matched
    }
}

/// `salt|hash`, both Base64: the hash is HMAC-SHA1 of the host under the
/// salt.
fn hashed_matches(hashed: &str, target: &str) -> bool {
    let Some((salt, hash)) = hashed.split_once('|') else { return false };
    let (Ok(salt), Ok(hash)) = (STANDARD.decode(salt), STANDARD.decode(hash)) else { return false };
    let Ok(mut mac) = Hmac::<Sha1>::new_from_slice(&salt) else { return false };
    mac.update(target.as_bytes());
    mac.verify_slice(&hash).is_ok()
}

/// `*` any run, `?` one character, the rest as is.
fn glob(pattern: &str, text: &str) -> bool {
    let (p, t): (Vec<char>, Vec<char>) = (pattern.chars().collect(), text.chars().collect());
    let (mut pi, mut ti) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star = Some((pi, ti));
            pi += 1;
        } else if let Some((sp, st)) = star {
            pi = sp + 1;
            ti = st + 1;
            star = Some((sp, st + 1));
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == '*' {
        pi += 1;
    }
    pi == p.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    const ED: &str = "AAAAC3NzaC1lZDI1NTE5AAAAIJdD7y3aLq454yWBdwLWbieU1ebz9/cu7/QEXn9OIeZJ";
    const ED2: &str = "AAAAC3NzaC1lZDI1NTE5AAAAILIG2T/B0l0gaqj3puu510tu9N1OkQ4znY3LYuEm5zCF";

    fn key(b64: &str) -> PublicKey {
        russh::keys::parse_public_key_base64(b64).unwrap()
    }

    fn with_files(lines: &str) -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let user = dir.path().join("known_hosts");
        fs::write(&user, lines).unwrap();
        let own = dir.path().join("own/known_hosts");
        use_files(vec![user], own.clone());
        (dir, own)
    }

    #[test]
    fn reads_lines_as_openssh_does() {
        // One test owns the files, as they are process-wide.
        let lines = format!(
            "# comment\n\
             host.lan,10.0.0.1 ssh-ed25519 {ED}\n\
             [other.lan]:2222\tssh-ed25519   {ED}\n\
             *.wild.lan,!bad.wild.lan ssh-ed25519 {ED}\n\
             @cert-authority *.lan ssh-ed25519 {ED2}\n\
             @revoked revoked.lan ssh-ed25519 {ED}\n\
             changed.lan ssh-ed25519 {ED2}\n\
             |1|O33ESRMWPVkMYIwJ1Uw+n877jTo=|nuuC5vEqXlEZ/8BXQR7m619W6Ak= ssh-ed25519 {ED2}\n"
        );
        let (_dir, own) = with_files(&lines);
        let k = key(ED);
        assert_eq!(check("host.lan", 22, &k), HostKeyCheck::Known);
        assert_eq!(check("HOST.lan", 22, &k), HostKeyCheck::Known);
        assert_eq!(check("10.0.0.1", 22, &k), HostKeyCheck::Known);
        assert_eq!(check("other.lan", 2222, &k), HostKeyCheck::Known);
        assert_eq!(check("other.lan", 22, &k), HostKeyCheck::Unknown);
        assert_eq!(check("a.wild.lan", 22, &k), HostKeyCheck::Known);
        assert_eq!(check("bad.wild.lan", 22, &k), HostKeyCheck::Unknown);
        assert!(matches!(check("revoked.lan", 22, &k), HostKeyCheck::Revoked { line: 6, .. }));
        assert!(matches!(check("changed.lan", 22, &k), HostKeyCheck::Changed { line: 7, .. }));
        assert_eq!(check("nowhere.lan", 22, &k), HostKeyCheck::Unknown);
        // The hashed line names `example.com` (russh's test vector).
        assert_eq!(check("example.com", 22, &key(ED2)), HostKeyCheck::Known);

        // Accepted keys land in Ferryx's file, and count from then on.
        remember("new.lan", 2200, &k).unwrap();
        assert!(fs::read_to_string(&own).unwrap().starts_with("[new.lan]:2200 ssh-ed25519 AAAA"));
        assert_eq!(check("new.lan", 2200, &k), HostKeyCheck::Known);
        assert!(matches!(check("new.lan", 2200, &key(ED2)), HostKeyCheck::Changed { .. }));
    }

    #[test]
    fn fingerprints_and_patterns() {
        assert!(fingerprint(&key(ED)).starts_with("SHA256:"));
        assert!(!fingerprint(&key(ED)).ends_with('='));
        assert_eq!(key_type(&key(ED)), "ssh-ed25519");
        assert!(glob("*.lan", "a.b.lan"));
        assert!(glob("h?st", "host"));
        assert!(!glob("h?st", "hoost"));
        assert!(glob("*", ""));
    }
}
