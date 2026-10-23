//! FTP, and FTPS with explicit TLS (`AUTH TLS`, data protected with
//! `PROT P`), through `suppaftp` on rustls. FTP carries one transfer per
//! control connection, so a server keeps a small pool of them: a listing
//! can run while a copy does. A connection idle for a minute is closed
//! (servers drop idle ones on their own anyway); one that dropped is
//! replaced by a new one, logged in with the password kept for the run.
//!
//! Passive mode (`EPSV` over IPv6), with the control connection's address
//! put in place of a private one a server behind NAT names. Listings are
//! `MLSD` where the server has it (`FEAT`), else `LIST`.

use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant, SystemTime};

use ferryx_core::entry::{Entry, EntryKind};
use parking_lot::{Condvar, Mutex};
use suppaftp::types::FileType;
use suppaftp::{FtpError, Mode, RustlsConnector, RustlsFtpStream, Status};

use super::address::{join, name, parent, ServerAddress};
use super::blocking::{self, watched, POLL};
use super::connection::{ConnectSpec, Notifier};
use super::entries::{entry, RemoteMeta};
use super::ftp_list::{mfmt_time, parse_list, parse_mlsx, Row};
use super::prompt::{self, Question};
use super::runtime::{Stop, CONNECT_TIMEOUT, REQUEST_TIMEOUT};
use super::{secrets, tls, Protocol, RemoteCaps, RemoteFs, RemoteRead, RemoteWrite};
use crate::error::{VfsError, VfsErrorKind, VfsResult};

type Conn = RustlsFtpStream;

/// Control connections one server may have at once.
const MAX_CONNECTIONS: usize = 3;

/// A connection idle this long is closed.
const IDLE: Duration = Duration::from_secs(60);

/// A connection idle this long is asked whether it is alive before use.
const STALE: Duration = Duration::from_secs(10);

/// What the server says it can do (`FEAT`).
#[derive(Clone, Copy, Debug, Default)]
struct Features {
    mlsd: bool,
    mfmt: bool,
    utf8: bool,
}

#[derive(Default)]
struct Pool {
    idle: Vec<(Instant, Conn)>,
    /// Connections open, idle or in use.
    open: usize,
}

/// One server over FTP or FTPS.
pub struct FtpFs {
    address: ServerAddress,
    user: String,
    password: Mutex<Option<String>>,
    notifier: Notifier,
    features: Mutex<Features>,
    pool: Mutex<Pool>,
    freed: Condvar,
    lost: AtomicBool,
    home: String,
}

impl FtpFs {
    /// Connects and logs in, asking for a password when none is kept.
    pub fn connect(spec: &ConnectSpec, notifier: Notifier, stop: Stop) -> VfsResult<FtpFs> {
        let address = spec.address.clone();
        let anonymous = address.user.is_empty() || address.user.eq_ignore_ascii_case("anonymous");
        let fs = FtpFs {
            user: if anonymous { "anonymous".to_string() } else { address.user.clone() },
            password: Mutex::new(if anonymous {
                Some(address.password.clone().unwrap_or_else(|| "anonymous@".to_string()))
            } else {
                address.password.clone()
            }),
            address: ServerAddress { password: None, ..address },
            notifier,
            features: Mutex::new(Features::default()),
            pool: Mutex::new(Pool::default()),
            freed: Condvar::new(),
            lost: AtomicBool::new(false),
            home: String::new(),
        };
        let mut conn = fs.log_in(stop)?;
        let features = match watched(control_socket(&conn), stop, || conn.feat()) {
            Ok(feat) => {
                let has = |name: &str| feat.keys().any(|k| k.eq_ignore_ascii_case(name));
                Features { mlsd: has("MLST"), mfmt: has("MFMT"), utf8: has("UTF8") }
            }
            Err(_) => Features::default(),
        };
        if features.utf8 {
            let _ = watched(control_socket(&conn), stop, || conn.opts("UTF8", Some("ON")));
        }
        *fs.features.lock() = features;
        let home =
            watched(control_socket(&conn), stop, || conn.pwd()).map_err(|e| fs.failed(e, None, stop))?;
        let fs = FtpFs { home: if home.starts_with('/') { home } else { "/".to_string() }, ..fs };
        fs.pool.lock().open = 1;
        fs.check_in(conn);
        Ok(fs)
    }

    /// A new control connection, logged in: with the password kept, the
    /// keychain's, or the user's (asked again while refused). The server
    /// is reached (and its certificate checked) before any password is
    /// looked for.
    fn log_in(&self, stop: Stop) -> VfsResult<Conn> {
        let server = self.address.key();
        let mut kept = self.password.lock().clone();
        let mut keychain_tried = false;
        let mut keychain_had = false;
        let mut retry = false;
        for _ in 0..5 {
            if stop() {
                return Err(VfsError::cancelled());
            }
            let mut conn = self.open_socket(stop)?;
            // The password kept, else the keychain's, else the user's.
            let (password, asked) = if let Some(password) = kept.take() {
                (password, None)
            } else if !keychain_tried {
                keychain_tried = true;
                match secrets::store().get(&server) {
                    Some(stored) => {
                        keychain_had = true;
                        (stored, None)
                    }
                    None => self.ask_password(retry, stop)?,
                }
            } else {
                self.ask_password(retry, stop)?
            };
            if asked.is_some() && watched(control_socket(&conn), stop, || conn.noop()).is_err() {
                // The server gave up waiting while the user typed.
                if stop() {
                    return Err(VfsError::cancelled());
                }
                conn = self.open_socket(stop)?;
            }
            match watched(control_socket(&conn), stop, || conn.login(self.user.as_str(), password.as_str())) {
                Ok(()) => {
                    if let Some(remember) = asked {
                        if remember {
                            let _ = secrets::store().set(&server, &password);
                        } else if keychain_had {
                            // The keychain's one is wrong and the new one
                            // is not to be kept: forget it.
                            let _ = secrets::store().delete(&server);
                        }
                    }
                    *self.password.lock() = Some(password);
                    let utf8 = self.features.lock().utf8;
                    let set_up = watched(control_socket(&conn), stop, || {
                        conn.transfer_type(FileType::Binary)?;
                        if utf8 {
                            let _ = conn.opts("UTF8", Some("ON"));
                        }
                        Ok(())
                    });
                    return set_up.map(|()| conn).map_err(|e| self.failed(e, None, stop));
                }
                Err(FtpError::UnexpectedResponse(response))
                    if matches!(
                        response.status,
                        Status::NotLoggedIn | Status::InvalidCredentials | Status::NeedPassword
                    ) =>
                {
                    let _ = conn.quit();
                    if self.user == "anonymous" {
                        break;
                    }
                    retry = true;
                }
                Err(error) => return Err(self.failed(error, None, stop)),
            }
        }
        Err(VfsError::new(
            VfsErrorKind::AuthFailed,
            None,
            format!("{}@{} did not accept the login", self.user, self.address.host),
        ))
    }

    /// The password from the user; `(password, Some(remember))`.
    fn ask_password(&self, retry: bool, stop: Stop) -> VfsResult<(String, Option<bool>)> {
        let answer = prompt::ask_blocking(
            Question::Password { server: self.address.key(), user: self.user.clone(), retry },
            stop,
        );
        if stop() {
            return Err(VfsError::cancelled());
        }
        match (answer.accept, answer.text()) {
            (true, Some(text)) => Ok((text.to_string(), Some(answer.remember))),
            _ => Err(VfsError::cancelled()),
        }
    }

    /// A control connection reaching the server, secured for FTPS, not
    /// logged in yet.
    fn open_socket(&self, stop: Stop) -> VfsResult<Conn> {
        let address = &self.address;
        let targets: Vec<SocketAddr> = (address.host.as_str(), address.port)
            .to_socket_addrs()
            .map_err(|e| super::sftp::unreachable_error(&e, address))?
            .collect();
        let mut last = None;
        let mut conn = None;
        for target in &targets {
            if stop() {
                return Err(VfsError::cancelled());
            }
            match blocking::connect(*target, CONNECT_TIMEOUT, stop) {
                Ok(socket) => {
                    conn = Some((socket, *target));
                    break;
                }
                Err(_) if stop() => return Err(VfsError::cancelled()),
                Err(e) => last = Some(e),
            }
        }
        let Some((socket, target)) = conn else {
            let error = last.unwrap_or_else(|| std::io::Error::other("no address"));
            return Err(super::sftp::unreachable_error(&error, address));
        };
        let _ = socket.set_read_timeout(Some(REQUEST_TIMEOUT));
        let _ = socket.set_write_timeout(Some(REQUEST_TIMEOUT));
        let _ = socket.set_nodelay(true);
        // The greeting and the TLS handshake wait on the server.
        watched(socket.try_clone().ok(), stop, || self.greet(socket, target))
            .map_err(|e| self.failed(e, None, stop))
    }

    /// The server's greeting read, passive mode set, TLS started for FTPS.
    fn greet(&self, socket: TcpStream, target: SocketAddr) -> Result<Conn, FtpError> {
        let address = &self.address;
        let mut conn = Conn::connect_with_stream(socket)?.passive_stream_builder(|addr| {
            let socket =
                TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT).map_err(FtpError::ConnectionError)?;
            let _ = socket.set_read_timeout(Some(REQUEST_TIMEOUT));
            let _ = socket.set_write_timeout(Some(REQUEST_TIMEOUT));
            Ok(socket)
        });
        if target.is_ipv6() {
            conn.set_mode(Mode::ExtendedPassive);
        } else {
            conn.set_mode(Mode::Passive);
            conn.set_passive_nat_workaround(true);
        }
        if address.protocol == Protocol::Ftps {
            let config = tls::client_config().map_err(|e| FtpError::SecureError(e.message))?;
            conn = conn.into_secure(RustlsConnector::from(config), &address.host)?;
        }
        Ok(conn)
    }

    /// `error` from a call a stop may have cut short: then
    /// [`VfsErrorKind::Cancelled`].
    fn failed(&self, error: FtpError, path: Option<&str>, stop: Stop) -> VfsError {
        if stop() {
            VfsError::cancelled()
        } else {
            ftp_error(error, path)
        }
    }

    /// A connection to work on: an idle one (checked when it sat a
    /// while), else a new one while there are fewer than
    /// [`MAX_CONNECTIONS`], else the next one freed.
    fn check_out(&self, stop: Stop) -> VfsResult<Conn> {
        loop {
            if stop() {
                return Err(VfsError::cancelled());
            }
            let mut pool = self.pool.lock();
            if let Some((since, mut conn)) = pool.idle.pop() {
                drop(pool);
                if since.elapsed() < STALE || watched(control_socket(&conn), stop, || conn.noop()).is_ok() {
                    return Ok(conn);
                }
                self.pool.lock().open -= 1;
                continue;
            }
            if pool.open < MAX_CONNECTIONS {
                pool.open += 1;
                drop(pool);
                return match self.log_in(stop) {
                    Ok(conn) => {
                        if self.lost.swap(false, Ordering::SeqCst) {
                            self.notifier.restored();
                        }
                        Ok(conn)
                    }
                    Err(error) => {
                        self.release();
                        if error.is_connection_error() && !self.lost.swap(true, Ordering::SeqCst) {
                            self.notifier.lost();
                        }
                        Err(error)
                    }
                };
            }
            self.freed.wait_for(&mut pool, Duration::from_millis(100));
        }
    }

    fn check_in(&self, conn: Conn) {
        self.pool.lock().idle.push((Instant::now(), conn));
        self.freed.notify_one();
    }

    /// A connection that broke (or a transfer abandoned on it) is closed,
    /// not given back.
    fn release(&self) {
        let mut pool = self.pool.lock();
        pool.open = pool.open.saturating_sub(1);
        drop(pool);
        self.freed.notify_one();
    }

    /// Runs `work` on a connection; a broken one is dropped and, for work
    /// that may run twice, the work tried again on a new one.
    fn with_conn<T>(
        &self,
        path: Option<&str>,
        again: bool,
        stop: Stop,
        mut work: impl FnMut(&mut Conn) -> Result<T, FtpError>,
    ) -> VfsResult<T> {
        let mut tried = false;
        loop {
            let mut conn = self.check_out(stop)?;
            match watched(control_socket(&conn), stop, || work(&mut conn)) {
                Ok(value) => {
                    self.check_in(conn);
                    return Ok(value);
                }
                Err(_) if stop() => {
                    // Shut under the call: of no use any more.
                    self.release();
                    return Err(VfsError::cancelled());
                }
                Err(error) => {
                    let error = ftp_error(error, path);
                    if error.is_connection_error() {
                        self.release();
                        if again && !tried {
                            tried = true;
                            continue;
                        }
                    } else {
                        self.check_in(conn);
                    }
                    return Err(error);
                }
            }
        }
    }

    fn rows(&self, dir: &str, stop: Stop) -> VfsResult<Vec<Row>> {
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        let mlsd = self.features.lock().mlsd;
        if mlsd {
            match self.with_conn(Some(dir), true, stop, |conn| conn.mlsd(Some(dir))) {
                Ok(lines) => return Ok(lines.iter().filter_map(|l| parse_mlsx(l)).collect()),
                Err(error) if error.kind == VfsErrorKind::Unsupported => self.features.lock().mlsd = false,
                Err(error) => return Err(error),
            }
        }
        let lines = self.with_conn(Some(dir), true, stop, |conn| conn.list(Some(dir)))?;
        Ok(lines.iter().filter_map(|l| parse_list(l, now)).collect())
    }

    fn reader(&self, path: &str, offset: u64, stop: Stop) -> VfsResult<FtpReader<'_>> {
        let mut conn = self.check_out(stop)?;
        let opened = watched(control_socket(&conn), stop, || {
            if offset > 0 {
                conn.resume_transfer(offset as usize)?;
            }
            conn.retr_as_stream(path)
        });
        match opened {
            Ok(stream) => {
                let data = Data::polled(stream.get_ref());
                Ok(FtpReader {
                    fs: self,
                    conn: Some(conn),
                    stream: Some(Box::new(stream)),
                    data,
                    path: path.to_string(),
                })
            }
            Err(_) if stop() => {
                self.release();
                Err(VfsError::cancelled())
            }
            Err(error) => {
                let error = ftp_error(error, Some(path));
                if error.is_connection_error() {
                    self.release();
                } else {
                    self.check_in(conn);
                }
                Err(error)
            }
        }
    }
}

impl RemoteFs for FtpFs {
    fn home(&self) -> String {
        self.home.clone()
    }

    fn caps(&self) -> RemoteCaps {
        RemoteCaps { set_modified: self.features.lock().mfmt, server_copy: false, recursive_delete: false }
    }

    fn list(&self, dir: &str, stop: Stop) -> VfsResult<Vec<Entry>> {
        Ok(self
            .rows(dir, stop)?
            .into_iter()
            .map(|row| entry(&row.name, join(dir, &row.name), row.meta))
            .collect())
    }

    fn stat(&self, path: &str, stop: Stop) -> VfsResult<Option<Entry>> {
        let Some(dir) = parent(path) else {
            return Ok(Some(entry(
                "/",
                "/".to_string(),
                RemoteMeta { kind: Some(EntryKind::Directory), ..Default::default() },
            )));
        };
        let wanted = name(path);
        match self.rows(&dir, stop) {
            Ok(rows) => Ok(rows
                .into_iter()
                .find(|r| r.name == wanted)
                .map(|row| entry(&row.name, path.to_string(), row.meta))),
            Err(error) if error.kind == VfsErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }

    fn read_range(&self, path: &str, offset: u64, len: usize, stop: Stop) -> VfsResult<Vec<u8>> {
        let mut reader = self.reader(path, offset, stop)?;
        let mut out = vec![0u8; len];
        let mut filled = 0;
        while filled < len {
            let n = reader.read(&mut out[filled..], stop)?;
            if n == 0 {
                break;
            }
            filled += n;
        }
        out.truncate(filled);
        Ok(out)
    }

    fn open_read<'a>(&'a self, path: &str, stop: Stop) -> VfsResult<Box<dyn RemoteRead + 'a>> {
        Ok(Box::new(self.reader(path, 0, stop)?))
    }

    fn create<'a>(
        &'a self,
        path: &str,
        _size: Option<u64>,
        stop: Stop,
    ) -> VfsResult<Box<dyn RemoteWrite + 'a>> {
        let mut conn = self.check_out(stop)?;
        match watched(control_socket(&conn), stop, || conn.put_with_stream(path)) {
            Ok(stream) => {
                let data = Data::polled(stream.get_ref());
                Ok(Box::new(FtpWriter {
                    fs: self,
                    conn: Some(conn),
                    stream: Some(Box::new(stream)),
                    data,
                    path: path.to_string(),
                }))
            }
            Err(_) if stop() => {
                self.release();
                Err(VfsError::cancelled())
            }
            Err(error) => {
                let error = ftp_error(error, Some(path));
                if error.is_connection_error() {
                    self.release();
                } else {
                    self.check_in(conn);
                }
                Err(error)
            }
        }
    }

    fn mkdir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        match self.with_conn(Some(path), false, stop, |conn| conn.mkdir(path)) {
            Err(error) if error.kind != VfsErrorKind::Cancelled && !error.is_connection_error() => {
                if self.stat(path, stop)?.is_some() {
                    Err(VfsError::remote(
                        VfsErrorKind::AlreadyExists,
                        Some(path),
                        format!("{path} already exists"),
                    ))
                } else {
                    Err(error)
                }
            }
            other => other,
        }
    }

    fn rename(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        // Many servers replace what is at the new name: never ours to do.
        if self.stat(to, stop)?.is_some() {
            return Err(VfsError::remote(
                VfsErrorKind::AlreadyExists,
                Some(to),
                format!("{to} already exists"),
            ));
        }
        self.with_conn(Some(from), false, stop, |conn| conn.rename(from, to))
    }

    fn remove_file(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.with_conn(Some(path), false, stop, |conn| conn.rm(path))
    }

    fn remove_dir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.with_conn(Some(path), false, stop, |conn| conn.rmdir(path))
    }

    fn set_modified(&self, path: &str, modified_ms: i64, stop: Stop) -> VfsResult<()> {
        if !self.features.lock().mfmt {
            return Err(VfsError::unsupported("this server cannot set a file's time"));
        }
        let Some(time) = mfmt_time(modified_ms) else { return Ok(()) };
        self.with_conn(Some(path), true, stop, |conn| {
            conn.custom_command(format!("MFMT {time} {path}"), &[Status::File]).map(|_| ())
        })
    }

    fn reconnect(&self, stop: Stop) -> VfsResult<()> {
        self.reap(Duration::ZERO);
        let conn = self.check_out(stop)?;
        self.check_in(conn);
        Ok(())
    }

    fn close(&self) {
        self.reap(Duration::ZERO);
    }

    fn reap_idle(&self) {
        self.reap(IDLE);
    }
}

impl FtpFs {
    /// Closes the connections idle for `longer` than that.
    fn reap(&self, longer: Duration) {
        let old: Vec<Conn> = {
            let mut pool = self.pool.lock();
            let (old, keep): (Vec<_>, Vec<_>) =
                pool.idle.drain(..).partition(|(since, _)| since.elapsed() >= longer);
            pool.idle = keep;
            pool.open = pool.open.saturating_sub(old.len());
            old.into_iter().map(|(_, conn)| conn).collect()
        };
        for mut conn in old {
            let _ = conn.get_ref().set_read_timeout(Some(Duration::from_secs(2)));
            let _ = conn.quit();
        }
    }
}

/// A file read over its own data connection; read to its end, the
/// control connection goes back to the pool, else it is closed (a
/// transfer cut short leaves it in no state to trust).
struct FtpReader<'a> {
    fs: &'a FtpFs,
    conn: Option<Conn>,
    stream: Option<Box<dyn std::io::Read + Send>>,
    data: Data,
    path: String,
}

impl RemoteRead for FtpReader<'_> {
    fn read(&mut self, buf: &mut [u8], stop: Stop) -> VfsResult<usize> {
        if stop() {
            return Err(VfsError::cancelled());
        }
        let Some(stream) = self.stream.as_mut() else { return Ok(0) };
        let mut waited = Duration::ZERO;
        let n = loop {
            match std::io::Read::read(stream, buf) {
                Ok(n) => break n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) if Data::is_wait(&e) => self.data.waited(&mut waited, stop, &self.path)?,
                Err(e) => return Err(io_error(&e, &self.path)),
            }
        };
        if n == 0 {
            let stream = self.stream.take().expect("checked above");
            let mut conn = self.conn.take().expect("a stream has its connection");
            self.data.settle();
            match watched(control_socket(&conn), stop, || conn.finalize_retr_stream(stream)) {
                Ok(()) => self.fs.check_in(conn),
                Err(error) => {
                    self.fs.release();
                    return Err(ftp_error(error, Some(&self.path)));
                }
            }
        }
        Ok(n)
    }
}

impl Drop for FtpReader<'_> {
    fn drop(&mut self) {
        if self.conn.take().is_some() {
            self.stream.take();
            self.fs.release();
        }
    }
}

/// A file written over its own data connection.
struct FtpWriter<'a> {
    fs: &'a FtpFs,
    conn: Option<Conn>,
    stream: Option<Box<dyn std::io::Write + Send>>,
    data: Data,
    path: String,
}

impl RemoteWrite for FtpWriter<'_> {
    fn write_all(&mut self, data: &[u8], stop: Stop) -> VfsResult<()> {
        if stop() {
            return Err(VfsError::cancelled());
        }
        let Some(stream) = self.stream.as_mut() else { return Err(lost(&self.path)) };
        let mut written = 0;
        let mut waited = Duration::ZERO;
        while written < data.len() {
            match std::io::Write::write(stream, &data[written..]) {
                Ok(0) => return Err(lost(&self.path)),
                Ok(n) => {
                    written += n;
                    waited = Duration::ZERO;
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) if Data::is_wait(&e) => self.data.waited(&mut waited, stop, &self.path)?,
                Err(e) => return Err(io_error(&e, &self.path)),
            }
        }
        Ok(())
    }

    fn finish(mut self: Box<Self>, stop: Stop) -> VfsResult<()> {
        let (Some(stream), Some(mut conn)) = (self.stream.take(), self.conn.take()) else {
            return Err(lost(&self.path));
        };
        // The last bytes and the server's word on them may take a while.
        self.data.settle();
        match watched(control_socket(&conn), stop, || conn.finalize_put_stream(stream)) {
            Ok(()) => {
                self.fs.check_in(conn);
                Ok(())
            }
            Err(error) => {
                let error = ftp_error(error, Some(&self.path));
                if error.is_connection_error() {
                    self.fs.release();
                } else {
                    self.fs.check_in(conn);
                }
                Err(error)
            }
        }
    }
}

impl Drop for FtpWriter<'_> {
    fn drop(&mut self) {
        if self.conn.take().is_some() {
            self.stream.take();
            self.fs.release();
        }
    }
}

/// A handle on the control connection's socket, for [`watched`] calls.
fn control_socket(conn: &Conn) -> Option<TcpStream> {
    conn.get_ref().try_clone().ok()
}

/// A data connection's socket: once the transfer is under way it waits in
/// slices of [`POLL`], so a stop is seen between them, and gives up after
/// [`REQUEST_TIMEOUT`] without a byte.
struct Data(Option<TcpStream>);

impl Data {
    fn polled(socket: &TcpStream) -> Data {
        let socket = socket.try_clone().ok();
        if let Some(socket) = &socket {
            let _ = socket.set_read_timeout(Some(POLL));
            let _ = socket.set_write_timeout(Some(POLL));
        }
        Data(socket)
    }

    /// A read or write that ran out of its slice.
    fn is_wait(error: &std::io::Error) -> bool {
        matches!(error.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut)
    }

    /// One more slice waited: stopped, or out of time, or wait on.
    fn waited(&self, waited: &mut Duration, stop: Stop, path: &str) -> VfsResult<()> {
        if stop() {
            return Err(VfsError::cancelled());
        }
        *waited += POLL;
        if self.0.is_none() || *waited >= REQUEST_TIMEOUT {
            return Err(VfsError::remote(
                VfsErrorKind::TimedOut,
                Some(path),
                format!("{path}: the server did not answer in time"),
            ));
        }
        Ok(())
    }

    /// The transfer's last words: back to the whole timeout, and the
    /// handle let go, so the socket closes with its stream (the server
    /// waits for that to answer).
    fn settle(&mut self) {
        if let Some(socket) = self.0.take() {
            let _ = socket.set_read_timeout(Some(REQUEST_TIMEOUT));
            let _ = socket.set_write_timeout(Some(REQUEST_TIMEOUT));
        }
    }
}

// ─── Errors ───

fn lost(path: &str) -> VfsError {
    VfsError::remote(
        VfsErrorKind::ConnectionLost,
        Some(path),
        format!("{path}: the connection to the server dropped"),
    )
}

fn io_error(error: &std::io::Error, path: &str) -> VfsError {
    if tls::is_certificate_error(error) {
        return VfsError::remote(
            VfsErrorKind::CertificateInvalid,
            Some(path),
            tls::certificate_message(error),
        );
    }
    let kind = match error.kind() {
        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => VfsErrorKind::TimedOut,
        _ => VfsErrorKind::ConnectionLost,
    };
    VfsError::remote(kind, Some(path), format!("{path}: {error}"))
}

/// A server's answer, worded by its code and its own text.
fn ftp_error(error: FtpError, path: Option<&str>) -> VfsError {
    let at = |message: String| match path {
        Some(path) => format!("{path}: {message}"),
        None => message,
    };
    match error {
        FtpError::ConnectionError(e) => {
            if tls::is_certificate_error(&e) {
                return VfsError::remote(
                    VfsErrorKind::CertificateInvalid,
                    path,
                    tls::certificate_message(&e),
                );
            }
            let kind = match e.kind() {
                std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => VfsErrorKind::TimedOut,
                _ => VfsErrorKind::ConnectionLost,
            };
            VfsError::remote(kind, path, at(e.to_string()))
        }
        FtpError::SecureError(message) => {
            let kind = if message.to_ascii_lowercase().contains("certificate") {
                VfsErrorKind::CertificateInvalid
            } else {
                VfsErrorKind::Io
            };
            VfsError::remote(kind, path, at(format!("TLS: {message}")))
        }
        FtpError::UnexpectedResponse(response) => {
            let text = String::from_utf8_lossy(&response.body).trim().to_string();
            let lower = text.to_ascii_lowercase();
            let kind = match response.status {
                Status::NotLoggedIn | Status::InvalidCredentials => VfsErrorKind::AuthFailed,
                Status::FileUnavailable if lower.contains("denied") || lower.contains("permission") => {
                    VfsErrorKind::PermissionDenied
                }
                Status::FileUnavailable
                    if lower.contains("exist")
                        && !lower.contains("not exist")
                        && !lower.contains("no such") =>
                {
                    VfsErrorKind::AlreadyExists
                }
                Status::FileUnavailable => VfsErrorKind::NotFound,
                Status::BadFilename => VfsErrorKind::InvalidName,
                Status::NotAvailable | Status::CannotOpenDataConnection | Status::TransferAborted => {
                    VfsErrorKind::ConnectionLost
                }
                Status::BadCommand
                | Status::NotImplemented
                | Status::NotImplementedParameter
                | Status::CommandNotImplemented => VfsErrorKind::Unsupported,
                _ => VfsErrorKind::Io,
            };
            VfsError::remote(kind, path, at(text))
        }
        FtpError::BadResponse => VfsError::remote(
            VfsErrorKind::ConnectionLost,
            path,
            at("the server's answer was cut short".to_string()),
        ),
        FtpError::InvalidAddress(e) => {
            VfsError::remote(VfsErrorKind::ConnectionLost, path, at(e.to_string()))
        }
    }
}
