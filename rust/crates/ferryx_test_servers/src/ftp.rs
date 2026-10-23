//! A small FTP server over a temporary folder, enough for Ferryx's FTP
//! client: login, `FEAT`, passive mode (`PASV`, `EPSV`), `LIST` (as `ls
//! -l` prints) and `MLSD`/`MLST` (which a test can leave out), `RETR`
//! with `REST`, `STOR`, `MKD`, `RMD`, `DELE`, `RNFR`/`RNTO`, `MFMT`,
//! `SIZE`; explicit TLS (`AUTH TLS`, `PBSZ`, `PROT P`); and a cut after so
//! many bytes sent, as a dropped network would cut it.

use std::fs;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use chrono::{DateTime, Utc};
use rustls::{ServerConfig, ServerConnection, StreamOwned};
use tempfile::TempDir;

/// How the server behaves.
#[derive(Clone)]
pub struct FtpOptions {
    pub user: String,
    pub password: String,
    /// `MLSD` and `MLST` (and `MLST` in `FEAT`); off, the client lists
    /// with `LIST`.
    pub mlsd: bool,
    /// `AUTH TLS` with this certificate.
    pub tls: Option<Arc<ServerConfig>>,
    /// Every connection is cut once this many bytes were sent by `RETR`.
    pub drop_after_bytes: Option<u64>,
    /// `RETR` goes silent after this many bytes, the connections left
    /// open (a server that hangs).
    pub stall_after_bytes: Option<u64>,
}

impl Default for FtpOptions {
    fn default() -> Self {
        FtpOptions {
            user: "me".into(),
            password: "secret".into(),
            mlsd: true,
            tls: None,
            drop_after_bytes: None,
            stall_after_bytes: None,
        }
    }
}

/// A running server; dropped, it stops and its folder goes.
pub struct FtpServer {
    pub port: u16,
    pub root: TempDir,
    /// Control connections accepted so far.
    pub connections: Arc<AtomicUsize>,
    /// Commands received, all connections together (`LIST`, `MLSD`…).
    pub commands: Arc<parking_lot::Mutex<Vec<String>>>,
    stop: Arc<AtomicBool>,
}

impl FtpServer {
    pub fn start(options: FtpOptions) -> FtpServer {
        let root = tempfile::tempdir().expect("a folder to serve");
        let listener = TcpListener::bind("127.0.0.1:0").expect("a port");
        let port = listener.local_addr().expect("an address").port();
        let stop = Arc::new(AtomicBool::new(false));
        let connections = Arc::new(AtomicUsize::new(0));
        let commands = Arc::new(parking_lot::Mutex::new(Vec::new()));
        let shared =
            Arc::new(Shared { root: root.path().to_path_buf(), options, commands: commands.clone() });
        {
            let stop = stop.clone();
            let connections = connections.clone();
            std::thread::spawn(move || {
                for stream in listener.incoming() {
                    if stop.load(Ordering::SeqCst) {
                        break;
                    }
                    let Ok(stream) = stream else { continue };
                    connections.fetch_add(1, Ordering::SeqCst);
                    let shared = shared.clone();
                    std::thread::spawn(move || {
                        let _ = Session::new(shared, stream).run();
                    });
                }
            });
        }
        FtpServer { port, root, connections, commands, stop }
    }

    pub fn path(&self, path: &str) -> PathBuf {
        self.root.path().join(path.trim_start_matches('/'))
    }
}

impl Drop for FtpServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        // Wakes the accepting thread.
        let _ = TcpStream::connect(("127.0.0.1", self.port));
    }
}

struct Shared {
    root: PathBuf,
    options: FtpOptions,
    commands: Arc<parking_lot::Mutex<Vec<String>>>,
}

enum Stream {
    Plain(TcpStream),
    Tls(Box<StreamOwned<ServerConnection, TcpStream>>),
}

impl Stream {
    fn tcp(&self) -> &TcpStream {
        match self {
            Stream::Plain(s) => s,
            Stream::Tls(s) => s.get_ref(),
        }
    }

    /// Ends a TLS stream as TLS asks (the peer reads to a clean end).
    fn close(mut self) {
        if let Stream::Tls(tls) = &mut self {
            tls.conn.send_close_notify();
            let _ = tls.flush();
        }
        let _ = self.tcp().shutdown(Shutdown::Both);
    }
}

impl Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Stream::Plain(s) => s.read(buf),
            Stream::Tls(s) => match s.read(buf) {
                Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => Ok(0),
                other => other,
            },
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            Stream::Plain(s) => s.write(buf),
            Stream::Tls(s) => s.write(buf),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self {
            Stream::Plain(s) => s.flush(),
            Stream::Tls(s) => s.flush(),
        }
    }
}

struct Session {
    shared: Arc<Shared>,
    control: Option<Stream>,
    user: Option<String>,
    logged_in: bool,
    cwd: String,
    passive: Option<TcpListener>,
    protect_data: bool,
    rest: u64,
    rename_from: Option<PathBuf>,
    sent: Arc<AtomicU64>,
}

impl Session {
    fn new(shared: Arc<Shared>, stream: TcpStream) -> Session {
        let _ = stream.set_read_timeout(Some(Duration::from_secs(60)));
        Session {
            shared,
            control: Some(Stream::Plain(stream)),
            user: None,
            logged_in: false,
            cwd: "/".into(),
            passive: None,
            protect_data: false,
            rest: 0,
            rename_from: None,
            sent: Arc::new(AtomicU64::new(0)),
        }
    }

    fn reply(&mut self, text: &str) -> io::Result<()> {
        let control = self.control.as_mut().ok_or(io::ErrorKind::NotConnected)?;
        control.write_all(text.as_bytes())?;
        control.write_all(b"\r\n")?;
        control.flush()
    }

    fn read_line(&mut self) -> io::Result<Option<String>> {
        let control = self.control.as_mut().ok_or(io::ErrorKind::NotConnected)?;
        let mut line = Vec::new();
        let mut byte = [0u8; 1];
        loop {
            if control.read(&mut byte)? == 0 {
                return Ok(None);
            }
            if byte[0] == b'\n' {
                break;
            }
            if byte[0] != b'\r' {
                line.push(byte[0]);
            }
        }
        Ok(Some(String::from_utf8_lossy(&line).into_owned()))
    }

    fn run(&mut self) -> io::Result<()> {
        self.reply("220 Ferryx test server")?;
        while let Some(line) = self.read_line()? {
            let (verb, arg) = match line.split_once(' ') {
                Some((v, a)) => (v.to_ascii_uppercase(), a.to_string()),
                None => (line.to_ascii_uppercase(), String::new()),
            };
            self.shared.commands.lock().push(verb.clone());
            if !self.logged_in
                && !matches!(
                    verb.as_str(),
                    "USER" | "PASS" | "AUTH" | "FEAT" | "QUIT" | "SYST" | "PBSZ" | "PROT" | "OPTS"
                )
            {
                self.reply("530 Please log in")?;
                continue;
            }
            if !self.command(&verb, &arg)? {
                break;
            }
        }
        Ok(())
    }

    fn local(&self, path: &str) -> PathBuf {
        let absolute =
            if path.starts_with('/') { path.to_string() } else { format!("{}/{}", self.cwd, path) };
        let mut out = self.shared.root.clone();
        for part in absolute.split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if out != self.shared.root {
                        out.pop();
                    }
                }
                other => out.push(other),
            }
        }
        out
    }

    /// Answers one command; `false` ends the session.
    fn command(&mut self, verb: &str, arg: &str) -> io::Result<bool> {
        match verb {
            "USER" => {
                self.user = Some(arg.to_string());
                self.reply("331 Password, please")?;
            }
            "PASS" => {
                let options = &self.shared.options;
                if self.user.as_deref() == Some(options.user.as_str()) && arg == options.password {
                    self.logged_in = true;
                    self.reply("230 Logged in")?;
                } else {
                    self.reply("530 Login incorrect")?;
                }
            }
            "SYST" => self.reply("215 UNIX Type: L8")?,
            "FEAT" => {
                let mut lines = vec!["211-Features:".to_string()];
                if self.shared.options.mlsd {
                    lines.push(" MLST type*;size*;modify*;UNIX.mode*;".into());
                }
                for feature in ["MFMT", "UTF8", "SIZE", "REST STREAM", "EPSV", "PASV"] {
                    lines.push(format!(" {feature}"));
                }
                if self.shared.options.tls.is_some() {
                    lines.extend([" AUTH TLS".to_string(), " PBSZ".to_string(), " PROT".to_string()]);
                }
                lines.push("211 End".into());
                self.reply(&lines.join("\r\n"))?;
            }
            "OPTS" | "TYPE" | "MODE" | "STRU" | "NOOP" => self.reply("200 OK")?,
            "PWD" | "XPWD" => {
                let cwd = self.cwd.replace('"', "\"\"");
                self.reply(&format!("257 \"{cwd}\" is the current folder"))?
            }
            "CWD" => {
                if self.local(arg).is_dir() {
                    self.cwd = normalize(&if arg.starts_with('/') {
                        arg.to_string()
                    } else {
                        format!("{}/{}", self.cwd, arg)
                    });
                    self.reply("250 OK")?;
                } else {
                    self.reply("550 No such folder")?;
                }
            }
            "AUTH" => match self.shared.options.tls.clone() {
                Some(config) if arg.eq_ignore_ascii_case("TLS") => {
                    self.reply("234 Go ahead")?;
                    let Some(Stream::Plain(tcp)) = self.control.take() else { return Ok(false) };
                    let conn = ServerConnection::new(config).map_err(io::Error::other)?;
                    self.control = Some(Stream::Tls(Box::new(StreamOwned::new(conn, tcp))));
                }
                _ => self.reply("502 No TLS here")?,
            },
            "PBSZ" => self.reply("200 PBSZ=0")?,
            "PROT" => {
                self.protect_data = arg.eq_ignore_ascii_case("P");
                self.reply("200 OK")?;
            }
            "PASV" => {
                let listener = TcpListener::bind("127.0.0.1:0")?;
                let port = listener.local_addr()?.port();
                self.passive = Some(listener);
                self.reply(&format!("227 Entering Passive Mode (127,0,0,1,{},{})", port >> 8, port & 0xff))?;
            }
            "EPSV" => {
                let listener = TcpListener::bind("127.0.0.1:0")?;
                let port = listener.local_addr()?.port();
                self.passive = Some(listener);
                self.reply(&format!("229 Entering Extended Passive Mode (|||{port}|)"))?;
            }
            "LIST" | "NLST" => {
                let path =
                    arg.split_whitespace().filter(|a| !a.starts_with('-')).collect::<Vec<_>>().join(" ");
                let dir = self.local(if path.is_empty() { "." } else { &path });
                match listing(&dir, false) {
                    Ok(lines) => self.send_lines(&lines)?,
                    Err(_) => self.reply("550 No such folder")?,
                }
            }
            "MLSD" if self.shared.options.mlsd => {
                let dir = self.local(if arg.is_empty() { "." } else { arg });
                match listing(&dir, true) {
                    Ok(lines) => self.send_lines(&lines)?,
                    Err(_) => self.reply("550 No such folder")?,
                }
            }
            "MLST" if self.shared.options.mlsd => {
                let path = self.local(if arg.is_empty() { "." } else { arg });
                match fs::symlink_metadata(&path) {
                    Ok(meta) => {
                        let name = arg.to_string();
                        self.reply(&format!("250-Listing\r\n {}\r\n250 End", facts(&meta, &name)))?;
                    }
                    Err(_) => self.reply("550 No such item")?,
                }
            }
            "SIZE" => match fs::metadata(self.local(arg)) {
                Ok(meta) if meta.is_file() => self.reply(&format!("213 {}", meta.len()))?,
                _ => self.reply("550 No such file")?,
            },
            "REST" => {
                self.rest = arg.parse().unwrap_or(0);
                self.reply("350 Restarting")?;
            }
            "RETR" => {
                let path = self.local(arg);
                let rest = std::mem::take(&mut self.rest);
                match fs::File::open(&path) {
                    Ok(mut file) if path.is_file() => {
                        file.seek(SeekFrom::Start(rest))?;
                        self.reply("150 Sending")?;
                        let Some(mut data) = self.accept_data()? else { return Ok(true) };
                        let mut buffer = vec![0u8; 16 * 1024];
                        loop {
                            let n = file.read(&mut buffer)?;
                            if n == 0 {
                                break;
                            }
                            let total = self.sent.fetch_add(n as u64, Ordering::SeqCst) + n as u64;
                            if self.shared.options.drop_after_bytes.is_some_and(|limit| total >= limit) {
                                // The network goes: both connections cut.
                                let _ = data.tcp().shutdown(Shutdown::Both);
                                if let Some(control) = self.control.take() {
                                    let _ = control.tcp().shutdown(Shutdown::Both);
                                }
                                return Ok(false);
                            }
                            if self.shared.options.stall_after_bytes.is_some_and(|limit| total >= limit) {
                                // Hangs, until the client gives up on it.
                                let mut probe = [0u8; 1];
                                let _ = data.tcp().set_read_timeout(None);
                                let _ = std::io::Read::read(&mut data.tcp(), &mut probe);
                                return Ok(false);
                            }
                            if data.write_all(&buffer[..n]).is_err() {
                                // The client let go (an abandoned read).
                                break;
                            }
                        }
                        data.close();
                        self.reply("226 Done")?;
                    }
                    _ => self.reply("550 No such file")?,
                }
            }
            "STOR" => {
                let path = self.local(arg);
                match fs::File::create(&path) {
                    Ok(mut file) => {
                        self.reply("150 Receiving")?;
                        let Some(mut data) = self.accept_data()? else { return Ok(true) };
                        io::copy(&mut data, &mut file)?;
                        data.close();
                        self.reply("226 Stored")?;
                    }
                    Err(_) => self.reply("553 Cannot write there")?,
                }
            }
            "MKD" => match fs::create_dir(self.local(arg)) {
                Ok(()) => self.reply(&format!("257 \"{arg}\" made"))?,
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => self.reply("550 File exists")?,
                Err(_) => self.reply("550 Cannot make it")?,
            },
            "RMD" => match fs::remove_dir(self.local(arg)) {
                Ok(()) => self.reply("250 Removed")?,
                Err(_) => self.reply("550 Cannot remove it")?,
            },
            "DELE" => match fs::remove_file(self.local(arg)) {
                Ok(()) => self.reply("250 Deleted")?,
                Err(_) => self.reply("550 No such file")?,
            },
            "RNFR" => {
                let path = self.local(arg);
                if path.symlink_metadata().is_ok() {
                    self.rename_from = Some(path);
                    self.reply("350 Ready")?;
                } else {
                    self.reply("550 No such item")?;
                }
            }
            "RNTO" => match self.rename_from.take() {
                // Replaces what is there, as many servers do.
                Some(from) => match fs::rename(from, self.local(arg)) {
                    Ok(()) => self.reply("250 Renamed")?,
                    Err(_) => self.reply("550 Cannot rename")?,
                },
                None => self.reply("503 RNFR first")?,
            },
            "MFMT" => {
                let (time, path) = arg.split_once(' ').unwrap_or((arg, ""));
                let parsed = chrono::NaiveDateTime::parse_from_str(time, "%Y%m%d%H%M%S");
                match parsed {
                    Ok(time) => {
                        let at = filetime::FileTime::from_unix_time(time.and_utc().timestamp(), 0);
                        match filetime::set_file_mtime(self.local(path), at) {
                            Ok(()) => self.reply(&format!("213 Modify={time}; {path}"))?,
                            Err(_) => self.reply("550 No such file")?,
                        }
                    }
                    Err(_) => self.reply("501 Bad time")?,
                }
            }
            "ABOR" => self.reply("226 Nothing to abort")?,
            "QUIT" => {
                self.reply("221 Bye")?;
                return Ok(false);
            }
            _ => self.reply("502 Not implemented")?,
        }
        Ok(true)
    }

    /// The data connection the client opens to the passive port.
    fn accept_data(&mut self) -> io::Result<Option<Stream>> {
        let Some(listener) = self.passive.take() else {
            self.reply("425 Use PASV first")?;
            return Ok(None);
        };
        listener.set_nonblocking(false)?;
        let (tcp, _) = listener.accept()?;
        let _ = tcp.set_read_timeout(Some(Duration::from_secs(30)));
        match (&self.shared.options.tls, self.protect_data) {
            (Some(config), true) => {
                let conn = ServerConnection::new(config.clone()).map_err(io::Error::other)?;
                Ok(Some(Stream::Tls(Box::new(StreamOwned::new(conn, tcp)))))
            }
            _ => Ok(Some(Stream::Plain(tcp))),
        }
    }

    fn send_lines(&mut self, lines: &[String]) -> io::Result<()> {
        self.reply("150 Here it comes")?;
        let Some(mut data) = self.accept_data()? else { return Ok(()) };
        for line in lines {
            data.write_all(line.as_bytes())?;
            data.write_all(b"\r\n")?;
        }
        data.close();
        self.reply("226 Done")
    }
}

fn normalize(path: &str) -> String {
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
    format!("/{}", parts.join("/"))
}

fn listing(dir: &std::path::Path, mlsd: bool) -> io::Result<Vec<String>> {
    let mut lines = Vec::new();
    if mlsd {
        let meta = fs::metadata(dir)?;
        lines.push(facts(&meta, ".").replace("type=dir", "type=cdir"));
    } else {
        lines.push("total 0".to_string());
    }
    for item in fs::read_dir(dir)? {
        let item = item?;
        let meta = fs::symlink_metadata(item.path())?;
        let name = item.file_name().to_string_lossy().into_owned();
        lines.push(if mlsd { facts(&meta, &name) } else { ls_line(&meta, &name, &item.path()) });
    }
    Ok(lines)
}

fn modified(meta: &fs::Metadata) -> DateTime<Utc> {
    DateTime::<Utc>::from(meta.modified().unwrap_or(SystemTime::UNIX_EPOCH))
}

fn mode(meta: &fs::Metadata) -> u32 {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        meta.mode() & 0o7777
    }
    #[cfg(not(unix))]
    {
        if meta.is_dir() {
            0o755
        } else {
            0o644
        }
    }
}

fn facts(meta: &fs::Metadata, name: &str) -> String {
    let kind = if meta.is_dir() {
        "dir"
    } else if meta.file_type().is_symlink() {
        "OS.unix=symlink"
    } else {
        "file"
    };
    format!(
        "type={kind};size={};modify={};UNIX.mode={:04o};UNIX.ownername=me; {name}",
        meta.len(),
        modified(meta).format("%Y%m%d%H%M%S"),
        mode(meta)
    )
}

fn ls_line(meta: &fs::Metadata, name: &str, path: &std::path::Path) -> String {
    let kind = if meta.is_dir() {
        'd'
    } else if meta.file_type().is_symlink() {
        'l'
    } else {
        '-'
    };
    let bits = mode(meta);
    let mut perms = String::with_capacity(10);
    perms.push(kind);
    for shift in [6, 3, 0] {
        let part = (bits >> shift) & 7;
        perms.push(if part & 4 != 0 { 'r' } else { '-' });
        perms.push(if part & 2 != 0 { 'w' } else { '-' });
        perms.push(if part & 1 != 0 { 'x' } else { '-' });
    }
    let time = modified(meta);
    let age = Utc::now().signed_duration_since(time);
    let when = if age.num_days() < 180 && age.num_days() > -1 {
        time.format("%b %e %H:%M").to_string()
    } else {
        time.format("%b %e  %Y").to_string()
    };
    let shown = if kind == 'l' {
        let target = fs::read_link(path).map(|t| t.to_string_lossy().into_owned()).unwrap_or_default();
        format!("{name} -> {target}")
    } else {
        name.to_string()
    };
    format!("{perms}    1 me       staff    {:>8} {when} {shown}", meta.len())
}
