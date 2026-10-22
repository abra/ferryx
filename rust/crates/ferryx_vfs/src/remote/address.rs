//! Where a server is: its protocol, host, port, user and the folder to
//! start in, read from an address the user types (`sftp://me@host/srv`)
//! and written back as the key every location on it carries.

use std::fmt::Write as _;

use percent_encoding::{percent_decode_str, utf8_percent_encode, AsciiSet, CONTROLS};

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// How Ferryx talks to a server.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Protocol {
    Sftp,
    /// Plain FTP: names, passwords and data cross unencrypted.
    Ftp,
    /// FTP with explicit TLS (`AUTH TLS` on the FTP port), data protected
    /// too (`PROT P`).
    Ftps,
    /// WebDAV over plain HTTP.
    Dav,
    /// WebDAV over HTTPS.
    Davs,
}

impl Protocol {
    pub const ALL: [Protocol; 5] =
        [Protocol::Sftp, Protocol::Ftp, Protocol::Ftps, Protocol::Dav, Protocol::Davs];

    /// The scheme of its addresses and keys.
    pub fn scheme(self) -> &'static str {
        match self {
            Protocol::Sftp => "sftp",
            Protocol::Ftp => "ftp",
            Protocol::Ftps => "ftps",
            Protocol::Dav => "dav",
            Protocol::Davs => "davs",
        }
    }

    pub fn default_port(self) -> u16 {
        match self {
            Protocol::Sftp => 22,
            Protocol::Ftp | Protocol::Ftps => 21,
            Protocol::Dav => 80,
            Protocol::Davs => 443,
        }
    }

    /// Whether what crosses the network is encrypted.
    pub fn is_secure(self) -> bool {
        matches!(self, Protocol::Sftp | Protocol::Ftps | Protocol::Davs)
    }

    /// The protocol a scheme names: Ferryx's own, and the ones people
    /// paste (`ssh`, `http`, `https`, `webdav`, `webdavs`).
    pub fn from_scheme(scheme: &str) -> Option<Protocol> {
        match scheme.to_ascii_lowercase().as_str() {
            "sftp" | "ssh" => Some(Protocol::Sftp),
            "ftp" => Some(Protocol::Ftp),
            "ftps" | "ftpes" => Some(Protocol::Ftps),
            "dav" | "webdav" | "http" => Some(Protocol::Dav),
            "davs" | "webdavs" | "https" => Some(Protocol::Davs),
            _ => None,
        }
    }
}

/// A server and the folder to open on it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ServerAddress {
    pub protocol: Protocol,
    /// Lower case; an IPv6 address without its brackets.
    pub host: String,
    pub port: u16,
    /// Empty: anonymous FTP, or WebDAV without a login, or (SFTP) the
    /// user of this computer.
    pub user: String,
    /// The folder to open, absolute and `/`-separated; empty for the
    /// server's own start (the home folder over SFTP and FTP).
    pub path: String,
    /// A password typed into the address (`ftp://me:secret@host`): used
    /// for this connection, never part of the key.
    pub password: Option<String>,
}

/// What a user name or a path segment keeps encoded in an address.
const COMPONENT: &AsciiSet = &CONTROLS
    .add(b' ')
    .add(b'"')
    .add(b'#')
    .add(b'%')
    .add(b'/')
    .add(b':')
    .add(b'?')
    .add(b'@')
    .add(b'[')
    .add(b']');

/// A path keeps its slashes.
const PATH: &AsciiSet = &CONTROLS.add(b' ').add(b'"').add(b'#').add(b'%').add(b'?');

impl ServerAddress {
    pub fn new(protocol: Protocol, host: &str, user: &str) -> ServerAddress {
        ServerAddress {
            protocol,
            host: normalize_host(host),
            port: protocol.default_port(),
            user: user.to_string(),
            path: String::new(),
            password: None,
        }
    }

    /// Reads an address as typed: `sftp://me@host:2222/srv/www`,
    /// `ftp://host`, `davs://me@cloud.example.com/remote.php/dav/files/me`,
    /// `https://…` (WebDAV), `[::1]`. Without a scheme it is
    /// `default_protocol`'s. User names and paths may be percent-encoded.
    pub fn parse(text: &str, default_protocol: Protocol) -> VfsResult<ServerAddress> {
        let text = text.trim();
        let invalid = |why: &str| VfsError::new(VfsErrorKind::InvalidName, None, format!("“{text}”: {why}"));
        let (protocol, rest) = match text.find("://") {
            Some(at) => {
                let scheme = &text[..at];
                let protocol = Protocol::from_scheme(scheme).ok_or_else(|| invalid("unknown protocol"))?;
                (protocol, &text[at + 3..])
            }
            None => (default_protocol, text),
        };
        let (authority, path) = match rest.find('/') {
            Some(at) => (&rest[..at], &rest[at..]),
            None => (rest, ""),
        };
        let (userinfo, hostport) = match authority.rfind('@') {
            Some(at) => (Some(&authority[..at]), &authority[at + 1..]),
            None => (None, authority),
        };
        let (user, password) = match userinfo {
            Some(info) => match info.find(':') {
                Some(colon) => (decode(&info[..colon]), Some(decode(&info[colon + 1..]))),
                None => (decode(info), None),
            },
            None => (String::new(), None),
        };
        let (host, port) = split_host_port(hostport).ok_or_else(|| invalid("no host"))?;
        if host.is_empty() {
            return Err(invalid("no host"));
        }
        if host.chars().any(|c| c.is_whitespace() || c.is_control()) {
            return Err(invalid("the host name is not valid"));
        }
        let port = match port {
            Some(port) => {
                port.parse::<u16>().ok().filter(|p| *p > 0).ok_or_else(|| invalid("the port is not valid"))?
            }
            None => protocol.default_port(),
        };
        let path = normalize(&decode(path.split(['?', '#']).next().unwrap_or("")));
        Ok(ServerAddress {
            protocol,
            host: normalize_host(host),
            port,
            user,
            password: password.filter(|p| !p.is_empty()),
            path,
        })
    }

    /// The server's key: `sftp://me@host:22`, every part spelled one way,
    /// so two addresses of one server and user meet in one connection.
    /// Never a password or a path.
    pub fn key(&self) -> String {
        let mut key = format!("{}://", self.protocol.scheme());
        if !self.user.is_empty() {
            let _ = write!(key, "{}@", utf8_percent_encode(&self.user, COMPONENT));
        }
        let _ = write!(key, "{}:{}", bracketed(&self.host), self.port);
        key
    }

    /// The address as a person reads it: `sftp://me@host`, with the port
    /// only when it is not the protocol's own.
    pub fn display_root(&self) -> String {
        let mut text = format!("{}://", self.protocol.scheme());
        if !self.user.is_empty() {
            let _ = write!(text, "{}@", self.user);
        }
        text.push_str(&bracketed(&self.host));
        if self.port != self.protocol.default_port() {
            let _ = write!(text, ":{}", self.port);
        }
        text
    }

    /// `path` on this server as a person reads it: `sftp://me@host/srv`.
    pub fn display_url(&self, path: &str) -> String {
        let root = self.display_root();
        if path.is_empty() || path == "/" {
            format!("{root}/")
        } else if path.starts_with('/') {
            format!("{root}{path}")
        } else {
            format!("{root}/{path}")
        }
    }

    /// `path` as a URL with its parts percent-encoded, for HTTP.
    pub fn http_url(&self, path: &str) -> String {
        let scheme = if self.protocol == Protocol::Davs { "https" } else { "http" };
        let mut url = format!("{scheme}://{}", bracketed(&self.host));
        if self.port != self.protocol.default_port() {
            let _ = write!(url, ":{}", self.port);
        }
        let path = if path.is_empty() { "/" } else { path };
        let _ = write!(url, "{}", utf8_percent_encode(path, PATH));
        url
    }

    /// The account the system's keychain keeps this server's password
    /// under: its key.
    pub fn keychain_account(&self) -> String {
        self.key()
    }
}

/// Reads the server's key back (see [`ServerAddress::key`]).
pub fn parse_key(key: &str) -> VfsResult<ServerAddress> {
    let address = ServerAddress::parse(key, Protocol::Sftp)?;
    if !key.contains("://") {
        return Err(VfsError::new(VfsErrorKind::InvalidName, None, format!("“{key}” is not a server")));
    }
    Ok(address)
}

fn decode(text: &str) -> String {
    percent_decode_str(text).decode_utf8_lossy().into_owned()
}

fn normalize_host(host: &str) -> String {
    host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase()
}

fn bracketed(host: &str) -> String {
    if host.contains(':') {
        format!("[{host}]")
    } else {
        host.to_string()
    }
}

/// `host`, `host:21`, `[::1]`, `[::1]:22`.
fn split_host_port(text: &str) -> Option<(&str, Option<&str>)> {
    if let Some(rest) = text.strip_prefix('[') {
        let close = rest.find(']')?;
        let host = &rest[..close];
        let after = &rest[close + 1..];
        return match after.strip_prefix(':') {
            Some(port) => Some((host, Some(port))),
            None if after.is_empty() => Some((host, None)),
            None => None,
        };
    }
    match text.rfind(':') {
        // A bare IPv6 address: colons, no port.
        Some(_) if text.matches(':').count() > 1 => Some((text, None)),
        Some(at) => Some((&text[..at], Some(&text[at + 1..]))),
        None => Some((text, None)),
    }
}

// ─── Paths on a server ───

/// `path` absolute, `/`-separated, without `.`, `..` or empty parts; `/`
/// for the root. Empty stays empty (the server's start).
pub fn normalize(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    let mut out = String::with_capacity(path.len() + 1);
    for part in &parts {
        out.push('/');
        out.push_str(part);
    }
    if out.is_empty() {
        out.push('/');
    }
    out
}

/// `dir/name`.
pub fn join(dir: &str, name: &str) -> String {
    if dir.is_empty() || dir == "/" {
        format!("/{name}")
    } else if dir.ends_with('/') {
        format!("{dir}{name}")
    } else {
        format!("{dir}/{name}")
    }
}

/// The folder `path` is in; `None` at the root.
pub fn parent(path: &str) -> Option<String> {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return None;
    }
    match trimmed.rfind('/') {
        Some(0) => Some("/".to_string()),
        Some(at) => Some(trimmed[..at].to_string()),
        None => None,
    }
}

/// The last part of `path`; empty at the root.
pub fn name(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    trimmed.rsplit('/').next().unwrap_or(trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_addresses() {
        let a = ServerAddress::parse("sftp://me@Example.COM:2222/srv/www", Protocol::Sftp).unwrap();
        assert_eq!(a.protocol, Protocol::Sftp);
        assert_eq!(a.host, "example.com");
        assert_eq!(a.port, 2222);
        assert_eq!(a.user, "me");
        assert_eq!(a.path, "/srv/www");
        assert_eq!(a.key(), "sftp://me@example.com:2222");
        assert_eq!(a.display_root(), "sftp://me@example.com:2222");
        assert_eq!(a.display_url("/srv"), "sftp://me@example.com:2222/srv");

        let ftp = ServerAddress::parse("ftp://host", Protocol::Sftp).unwrap();
        assert_eq!((ftp.port, ftp.user.as_str(), ftp.path.as_str()), (21, "", ""));
        assert_eq!(ftp.key(), "ftp://host:21");
        assert_eq!(ftp.display_root(), "ftp://host");

        let https =
            ServerAddress::parse("https://cloud.example.com/remote.php/dav/files/me/", Protocol::Sftp)
                .unwrap();
        assert_eq!(https.protocol, Protocol::Davs);
        assert_eq!(https.port, 443);
        assert_eq!(https.path, "/remote.php/dav/files/me");
        assert_eq!(https.http_url("/a b/ü"), "https://cloud.example.com/a%20b/%C3%BC");
    }

    #[test]
    fn passwords_never_reach_the_key() {
        let a = ServerAddress::parse("ftp://me%40mail.com:p%3Ass@host/", Protocol::Ftp).unwrap();
        assert_eq!(a.user, "me@mail.com");
        assert_eq!(a.password.as_deref(), Some("p:ss"));
        assert_eq!(a.key(), "ftp://me%40mail.com@host:21");
        assert_eq!(parse_key(&a.key()).unwrap().user, "me@mail.com");
        assert_eq!(a.path, "/");
    }

    #[test]
    fn hosts_by_name_and_number() {
        let v6 = ServerAddress::parse("sftp://[::1]:2200", Protocol::Sftp).unwrap();
        assert_eq!(v6.host, "::1");
        assert_eq!(v6.key(), "sftp://[::1]:2200");
        let bare = ServerAddress::parse("me@host.lan", Protocol::Sftp).unwrap();
        assert_eq!((bare.user.as_str(), bare.host.as_str(), bare.port), ("me", "host.lan", 22));
        assert!(ServerAddress::parse("sftp://", Protocol::Sftp).is_err());
        assert!(ServerAddress::parse("sftp://host:99999", Protocol::Sftp).is_err());
        assert!(ServerAddress::parse("gopher://host", Protocol::Sftp).is_err());
        assert!(ServerAddress::parse("sftp://ho st", Protocol::Sftp).is_err());
    }

    #[test]
    fn paths_on_a_server() {
        assert_eq!(normalize("/a//b/./c/../d/"), "/a/b/d");
        assert_eq!(normalize("/.."), "/");
        assert_eq!(normalize(""), "");
        assert_eq!(join("/", "a"), "/a");
        assert_eq!(join("/a", "b"), "/a/b");
        assert_eq!(parent("/a/b"), Some("/a".to_string()));
        assert_eq!(parent("/a"), Some("/".to_string()));
        assert_eq!(parent("/"), None);
        assert_eq!(name("/a/b"), "b");
        assert_eq!(name("/"), "");
    }
}
