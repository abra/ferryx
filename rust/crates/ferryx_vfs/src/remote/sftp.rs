//! SFTP over SSH: `russh` for the connection, `russh-sftp` for the file
//! protocol (version 3, OpenSSH's). One SSH connection per server with one
//! SFTP session on it, shared by every listing and transfer (the protocol
//! numbers its requests, so they interleave); a dropped connection is
//! opened again on the next call with the credentials kept for the run.
//!
//! Host keys are checked against the known_hosts files (see
//! [`known_hosts`]); logging in goes as OpenSSH's does: the agent's keys,
//! the default key files, the server's own prompts, a password. Reads and
//! writes keep several requests in flight, as OpenSSH's client does, so a
//! distant server is not paid a round trip per block.

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use ferryx_core::entry::{Entry, EntryKind};
use parking_lot::Mutex;
use russh::client::{self, AuthResult, Handle, KeyboardInteractiveAuthResponse};
use russh::keys::{PrivateKey, PrivateKeyWithHashAlg, PublicKey, PublicKeyOrCertificate};
use russh::MethodKind;
use russh_sftp::client::error::Error as SftpError;
use russh_sftp::client::RawSftpSession;
use russh_sftp::protocol::{Data, File, FileAttributes, OpenFlags, Status, StatusCode};
use tokio::sync::watch;
use tokio::task::JoinHandle;

use super::address::{join, ServerAddress};
use super::connection::{AuthMethod, ConnectSpec, Notifier};
use super::entries::{entry, kind_of_mode, mode_of_text, RemoteMeta};
use super::known_hosts::{self, HostKeyCheck};
use super::prompt::{self, Answer, Question};
use super::runtime::{self, run, run_unbounded, timed_out, Stop, CONNECT_TIMEOUT, REQUEST_TIMEOUT};
use super::secrets;
use super::{RemoteCaps, RemoteFs, RemoteRead, RemoteWrite};
use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// Bytes one read or write request asks for: under every server's limit
/// (OpenSSH takes up to 256 KiB), large enough to keep requests few.
const CHUNK: u32 = 64 * 1024;

/// Requests kept in flight by a read or a write: 1 MiB, as OpenSSH's
/// client keeps 64 of 32 KiB.
const IN_FLIGHT: usize = 16;

/// How often an idle SSH connection says it is alive, so neither side
/// nor a router in between drops it.
const KEEPALIVE: Duration = Duration::from_secs(30);

/// What the run keeps to open the connection again without asking twice.
#[derive(Default)]
struct Credentials {
    password: Option<String>,
    passphrases: HashMap<PathBuf, String>,
    /// The host key trusted this run: the same key on a later connection
    /// needs no question; another one is refused.
    host_key: Option<PublicKey>,
    /// The keychain's password was refused once: ask instead.
    keychain_failed: bool,
    /// A password was refused: the next one asked for says so.
    password_refused: bool,
}

/// Connections a login may take: a server that takes one password per
/// connection gets a new one for each try.
const LOGIN_ROUNDS: usize = 4;

/// One server over SFTP.
pub struct SftpFs {
    spec: ConnectSpec,
    notifier: Notifier,
    credentials: Arc<Mutex<Credentials>>,
    link: Mutex<Option<Arc<Link>>>,
    home: String,
}

/// An SSH connection with its SFTP session.
struct Link {
    handle: Handle<Client>,
    sftp: Arc<RawSftpSession>,
    closed: Arc<AtomicBool>,
    /// Turns `true`, or loses its sender, when the connection ends.
    gone: watch::Receiver<bool>,
}

impl Link {
    fn alive(&self) -> bool {
        !self.closed.load(Ordering::SeqCst) && !self.handle.is_closed()
    }

    /// `work` on this connection, failed as soon as the connection ends:
    /// requests it left unanswered would wait for their timeout.
    async fn on<T>(&self, work: impl Future<Output = VfsResult<T>>) -> VfsResult<T> {
        let mut gone = self.gone.clone();
        tokio::select! {
            biased;
            result = work => result,
            _ = gone.wait_for(|gone| *gone) => Err(lost()),
        }
    }
}

impl SftpFs {
    /// Connects and logs in to `spec`'s server, asking the user what it
    /// must (a host key, a password, a passphrase) through [`prompt`].
    pub fn connect(spec: &ConnectSpec, notifier: Notifier, stop: Stop) -> VfsResult<SftpFs> {
        let credentials = Arc::new(Mutex::new(Credentials {
            password: spec.address.password.clone(),
            ..Default::default()
        }));
        let link = run_unbounded(open_link(spec, credentials.clone(), notifier.clone()), stop)?;
        let home = run(
            link.on(async {
                let name = link.sftp.realpath(".").await.map_err(|e| sftp_error(e, Some(".")))?;
                Ok(name.files.first().map(|f| f.filename.clone()).unwrap_or_else(|| "/".to_string()))
            }),
            REQUEST_TIMEOUT,
            stop,
        )?;
        let mut spec = spec.clone();
        spec.address.password = None;
        Ok(SftpFs { spec, notifier, credentials, link: Mutex::new(Some(Arc::new(link))), home })
    }

    /// The open link, or a new one when it dropped.
    fn link(&self, stop: Stop) -> VfsResult<Arc<Link>> {
        let mut slot = self.link.lock();
        if let Some(link) = slot.as_ref() {
            if link.alive() {
                return Ok(link.clone());
            }
            self.notifier.lost();
        }
        *slot = None;
        let link = Arc::new(run_unbounded(
            open_link(&self.spec, self.credentials.clone(), self.notifier.clone()),
            stop,
        )?);
        *slot = Some(link.clone());
        self.notifier.restored();
        Ok(link)
    }

    /// Drops `link` after it failed, so the next call opens a new one.
    fn forget(&self, link: &Arc<Link>) {
        let mut slot = self.link.lock();
        if slot.as_ref().is_some_and(|current| Arc::ptr_eq(current, link)) {
            link.closed.store(true, Ordering::SeqCst);
            *slot = None;
            self.notifier.lost();
        }
    }

    /// Runs `call` on the session; a call that may run twice (a read) is
    /// tried once more on a new connection when the first one dropped.
    fn call<T, F, Fut>(&self, path: Option<&str>, again: bool, stop: Stop, call: F) -> VfsResult<T>
    where
        F: Fn(Arc<RawSftpSession>) -> Fut,
        Fut: Future<Output = Result<T, SftpError>>,
    {
        let mut tried = false;
        loop {
            let link = self.link(stop)?;
            let result = run(
                link.on(async { call(link.sftp.clone()).await.map_err(|e| sftp_error(e, path)) }),
                REQUEST_TIMEOUT,
                stop,
            );
            match result {
                Err(error) if error.is_connection_error() => {
                    self.forget(&link);
                    if again && !tried {
                        tried = true;
                        continue;
                    }
                    return Err(error);
                }
                other => return other,
            }
        }
    }

    fn reads(&self, path: &str, offset: u64, stop: Stop) -> VfsResult<SftpReader<'_>> {
        let link = self.link(stop)?;
        let handle = run(
            link.on(async {
                link.sftp
                    .open(path, OpenFlags::READ, FileAttributes::empty())
                    .await
                    .map(|h| h.handle)
                    .map_err(|e| sftp_error(e, Some(path)))
            }),
            REQUEST_TIMEOUT,
            stop,
        )
        .inspect_err(|e| {
            if e.is_connection_error() {
                self.forget(&link);
            }
        })?;
        Ok(SftpReader {
            fs: self,
            link,
            path: path.to_string(),
            handle,
            next: offset,
            limit: None,
            queue: VecDeque::new(),
            buffer: Vec::new(),
            at: 0,
            eof: false,
        })
    }
}

impl RemoteFs for SftpFs {
    fn home(&self) -> String {
        self.home.clone()
    }

    fn caps(&self) -> RemoteCaps {
        RemoteCaps { set_modified: true, server_copy: false, recursive_delete: false }
    }

    fn list(&self, dir: &str, stop: Stop) -> VfsResult<Vec<Entry>> {
        let files = self.call(Some(dir), true, stop, |sftp| async move {
            let handle = sftp.opendir(dir).await?.handle;
            let mut files = Vec::new();
            let outcome = loop {
                match sftp.readdir(handle.as_str()).await {
                    Ok(name) => files.extend(name.files),
                    Err(SftpError::Status(status)) if status.status_code == StatusCode::Eof => break Ok(()),
                    Err(error) => break Err(error),
                }
            };
            let _ = sftp.close(handle).await;
            outcome.map(|()| files)
        })?;
        let rows: Vec<File> = files.into_iter().filter(|f| f.filename != "." && f.filename != "..").collect();
        // Where the links lead, asked all at once.
        let links: Vec<String> = rows
            .iter()
            .filter(|f| kind_of_mode(f.attrs.permissions.unwrap_or(0)) == Some(EntryKind::Symlink))
            .map(|f| join(dir, &f.filename))
            .collect();
        let targets = if links.is_empty() {
            HashMap::new()
        } else {
            self.call(Some(dir), true, stop, |sftp| {
                let links = links.clone();
                async move {
                    let asked = links.iter().map(|path| {
                        let sftp = sftp.clone();
                        async move {
                            let target = sftp
                                .readlink(path.as_str())
                                .await
                                .ok()
                                .and_then(|n| n.files.first().map(|f| f.filename.clone()));
                            let to_dir =
                                sftp.stat(path.as_str()).await.ok().is_some_and(|a| a.attrs.is_dir());
                            (path.clone(), (target, to_dir))
                        }
                    });
                    Ok(futures_util::future::join_all(asked).await.into_iter().collect::<HashMap<_, _>>())
                }
            })?
        };
        Ok(rows
            .into_iter()
            .map(|file| {
                let path = join(dir, &file.filename);
                let mut meta = meta_of(&file.attrs, Some(&file.longname));
                if let Some((target, to_dir)) = targets.get(&path) {
                    meta.symlink_target = target.clone();
                    meta.link_to_dir = *to_dir;
                }
                entry(&file.filename, path, meta)
            })
            .collect())
    }

    fn stat(&self, path: &str, stop: Stop) -> VfsResult<Option<Entry>> {
        let found = self.call(Some(path), true, stop, |sftp| async move {
            let attrs = match sftp.lstat(path).await {
                Ok(attrs) => attrs.attrs,
                Err(SftpError::Status(status)) if status.status_code == StatusCode::NoSuchFile => {
                    return Ok(None)
                }
                Err(error) => return Err(error),
            };
            let mut meta = meta_of(&attrs, None);
            if meta.kind == Some(EntryKind::Symlink) {
                meta.symlink_target =
                    sftp.readlink(path).await.ok().and_then(|n| n.files.first().map(|f| f.filename.clone()));
                meta.link_to_dir = sftp.stat(path).await.ok().is_some_and(|a| a.attrs.is_dir());
            }
            Ok(Some(meta))
        })?;
        Ok(found.map(|meta| entry(super::address::name(path), path.to_string(), meta)))
    }

    fn read_range(&self, path: &str, offset: u64, len: usize, stop: Stop) -> VfsResult<Vec<u8>> {
        let mut reader = self.reads(path, offset, stop)?;
        reader.limit = Some(offset + len as u64);
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
        Ok(Box::new(self.reads(path, 0, stop)?))
    }

    fn create<'a>(
        &'a self,
        path: &str,
        _size: Option<u64>,
        stop: Stop,
    ) -> VfsResult<Box<dyn RemoteWrite + 'a>> {
        let link = self.link(stop)?;
        let handle = run(
            async {
                link.sftp
                    .open(
                        path,
                        OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::TRUNCATE,
                        FileAttributes::empty(),
                    )
                    .await
                    .map(|h| h.handle)
                    .map_err(|e| sftp_error(e, Some(path)))
            },
            REQUEST_TIMEOUT,
            stop,
        )
        .inspect_err(|e| {
            if e.is_connection_error() {
                self.forget(&link);
            }
        })?;
        Ok(Box::new(SftpWriter {
            fs: self,
            link,
            path: path.to_string(),
            handle: Some(handle),
            offset: 0,
            buffer: Vec::with_capacity(CHUNK as usize),
            pending: VecDeque::new(),
        }))
    }

    fn mkdir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        let made = self.call(Some(path), false, stop, |sftp| async move {
            match sftp.mkdir(path, FileAttributes::empty()).await {
                Ok(_) => Ok(true),
                // OpenSSH says only "failure" for an item already there.
                Err(SftpError::Status(status)) if status.status_code == StatusCode::Failure => {
                    match sftp.lstat(path).await {
                        Ok(_) => Ok(false),
                        Err(_) => Err(SftpError::Status(status)),
                    }
                }
                Err(error) => Err(error),
            }
        })?;
        if made {
            Ok(())
        } else {
            Err(VfsError::remote(VfsErrorKind::AlreadyExists, Some(path), format!("{path} already exists")))
        }
    }

    fn rename(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        let taken = self.call(Some(from), false, stop, |sftp| async move {
            if sftp.lstat(to).await.is_ok() {
                return Ok(true);
            }
            sftp.rename(from, to).await.map(|_| false)
        })?;
        if taken {
            return Err(VfsError::remote(
                VfsErrorKind::AlreadyExists,
                Some(to),
                format!("{to} already exists"),
            ));
        }
        Ok(())
    }

    fn remove_file(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.call(Some(path), false, stop, |sftp| async move { sftp.remove(path).await.map(|_| ()) })
    }

    fn remove_dir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.call(Some(path), false, stop, |sftp| async move { sftp.rmdir(path).await.map(|_| ()) })
    }

    fn set_modified(&self, path: &str, modified_ms: i64, stop: Stop) -> VfsResult<()> {
        let seconds = u32::try_from(modified_ms.div_euclid(1000)).unwrap_or(0);
        self.call(Some(path), true, stop, |sftp| async move {
            let attrs =
                FileAttributes { atime: Some(seconds), mtime: Some(seconds), ..FileAttributes::empty() };
            sftp.setstat(path, attrs).await.map(|_| ())
        })
    }

    fn reconnect(&self, stop: Stop) -> VfsResult<()> {
        if let Some(link) = self.link.lock().take() {
            link.closed.store(true, Ordering::SeqCst);
        }
        self.link(stop).map(|_| ())
    }

    fn close(&self) {
        let Some(link) = self.link.lock().take() else { return };
        link.closed.store(true, Ordering::SeqCst);
        let _ = run(
            async {
                let _ = link.sftp.close_session();
                let _ = link.handle.disconnect(russh::Disconnect::ByApplication, "", "en").await;
                Ok(())
            },
            Duration::from_secs(2),
            &runtime::never,
        );
    }
}

// ─── Reading and writing ───

type ReadTask = JoinHandle<Result<Data, SftpError>>;

/// A file read with requests kept in flight, put back in order; a short
/// answer has its rest asked for again before what follows.
struct SftpReader<'a> {
    fs: &'a SftpFs,
    link: Arc<Link>,
    path: String,
    handle: String,
    /// The offset of the next request.
    next: u64,
    /// Where reading stops (a range's end).
    limit: Option<u64>,
    queue: VecDeque<(u64, u32, ReadTask)>,
    buffer: Vec<u8>,
    at: usize,
    eof: bool,
}

impl SftpReader<'_> {
    fn ask(&self, offset: u64, len: u32) -> ReadTask {
        let sftp = self.link.sftp.clone();
        let handle = self.handle.clone();
        runtime::runtime().spawn(async move { sftp.read(handle, offset, len).await })
    }

    fn fill(&mut self) {
        while !self.eof && self.queue.len() < IN_FLIGHT {
            let len = match self.limit {
                Some(limit) if self.next >= limit => break,
                Some(limit) => CHUNK.min((limit - self.next) as u32),
                None => CHUNK,
            };
            let task = self.ask(self.next, len);
            self.queue.push_back((self.next, len, task));
            self.next += u64::from(len);
        }
    }

    fn give_up(&mut self) {
        for (_, _, task) in self.queue.drain(..) {
            task.abort();
        }
    }
}

impl RemoteRead for SftpReader<'_> {
    fn read(&mut self, out: &mut [u8], stop: Stop) -> VfsResult<usize> {
        loop {
            if self.at < self.buffer.len() {
                let n = out.len().min(self.buffer.len() - self.at);
                out[..n].copy_from_slice(&self.buffer[self.at..self.at + n]);
                self.at += n;
                return Ok(n);
            }
            self.fill();
            let Some((offset, len, task)) = self.queue.pop_front() else { return Ok(0) };
            let path = self.path.clone();
            let answer = run(
                self.link.on(async move {
                    match task.await {
                        Ok(Ok(data)) => Ok(Some(data.data)),
                        Ok(Err(SftpError::Status(status))) if status.status_code == StatusCode::Eof => {
                            Ok(None)
                        }
                        Ok(Err(error)) => Err(sftp_error(error, Some(&path))),
                        Err(_) => Err(lost()),
                    }
                }),
                REQUEST_TIMEOUT,
                stop,
            );
            match answer {
                Ok(Some(data)) if !data.is_empty() => {
                    let got = data.len() as u32;
                    if got < len {
                        // The rest of this block comes before the next ones.
                        let rest = self.ask(offset + u64::from(got), len - got);
                        self.queue.push_front((offset + u64::from(got), len - got, rest));
                    }
                    self.buffer = data;
                    self.at = 0;
                }
                Ok(_) => {
                    self.eof = true;
                    self.give_up();
                }
                Err(error) => {
                    self.give_up();
                    if error.is_connection_error() {
                        self.fs.forget(&self.link);
                    }
                    return Err(error);
                }
            }
        }
    }
}

impl Drop for SftpReader<'_> {
    fn drop(&mut self) {
        self.give_up();
        let sftp = self.link.sftp.clone();
        let handle = std::mem::take(&mut self.handle);
        runtime::runtime().spawn(async move {
            let _ = sftp.close(handle).await;
        });
    }
}

type WriteTask = JoinHandle<Result<Status, SftpError>>;

/// A file written with requests kept in flight; each answer is checked,
/// the oldest first, before more than [`IN_FLIGHT`] wait.
struct SftpWriter<'a> {
    fs: &'a SftpFs,
    link: Arc<Link>,
    path: String,
    handle: Option<String>,
    offset: u64,
    buffer: Vec<u8>,
    pending: VecDeque<WriteTask>,
}

impl SftpWriter<'_> {
    fn send(&mut self, stop: Stop) -> VfsResult<()> {
        if self.buffer.is_empty() {
            return Ok(());
        }
        let data = std::mem::replace(&mut self.buffer, Vec::with_capacity(CHUNK as usize));
        let len = data.len() as u64;
        let sftp = self.link.sftp.clone();
        let handle = self.handle.clone().unwrap_or_default();
        let offset = self.offset;
        self.pending
            .push_back(runtime::runtime().spawn(async move { sftp.write(handle, offset, data).await }));
        self.offset += len;
        while self.pending.len() >= IN_FLIGHT {
            self.settle_one(stop)?;
        }
        Ok(())
    }

    fn settle_one(&mut self, stop: Stop) -> VfsResult<()> {
        let Some(task) = self.pending.pop_front() else { return Ok(()) };
        let path = self.path.clone();
        let outcome = run(
            self.link.on(async move {
                match task.await {
                    Ok(Ok(_)) => Ok(()),
                    Ok(Err(error)) => Err(sftp_error(error, Some(&path))),
                    Err(_) => Err(lost()),
                }
            }),
            REQUEST_TIMEOUT,
            stop,
        );
        if let Err(error) = &outcome {
            if error.is_connection_error() {
                self.fs.forget(&self.link);
            }
        }
        outcome
    }
}

impl RemoteWrite for SftpWriter<'_> {
    fn write_all(&mut self, mut data: &[u8], stop: Stop) -> VfsResult<()> {
        while !data.is_empty() {
            let room = CHUNK as usize - self.buffer.len();
            let n = room.min(data.len());
            self.buffer.extend_from_slice(&data[..n]);
            data = &data[n..];
            if self.buffer.len() == CHUNK as usize {
                self.send(stop)?;
            }
        }
        Ok(())
    }

    fn finish(mut self: Box<Self>, stop: Stop) -> VfsResult<()> {
        self.send(stop)?;
        while !self.pending.is_empty() {
            self.settle_one(stop)?;
        }
        let handle = self.handle.take().unwrap_or_default();
        let sftp = self.link.sftp.clone();
        let path = self.path.clone();
        run(
            self.link.on(async move {
                sftp.close(handle).await.map(|_| ()).map_err(|e| sftp_error(e, Some(&path)))
            }),
            REQUEST_TIMEOUT,
            stop,
        )
    }
}

impl Drop for SftpWriter<'_> {
    fn drop(&mut self) {
        for task in self.pending.drain(..) {
            task.abort();
        }
        if let Some(handle) = self.handle.take() {
            let sftp = self.link.sftp.clone();
            runtime::runtime().spawn(async move {
                let _ = sftp.close(handle).await;
            });
        }
    }
}

// ─── Rows ───

fn meta_of(attrs: &FileAttributes, longname: Option<&str>) -> RemoteMeta {
    let mode = attrs.permissions;
    let mut meta = RemoteMeta {
        kind: mode.and_then(kind_of_mode).or(Some(EntryKind::File)),
        size: attrs.size,
        modified_ms: attrs.mtime.map(|s| i64::from(s) * 1000),
        accessed_ms: attrs.atime.map(|s| i64::from(s) * 1000),
        mode,
        uid: attrs.uid,
        gid: attrs.gid,
        owner: attrs.user.clone().unwrap_or_default(),
        group: attrs.group.clone().unwrap_or_default(),
        ..Default::default()
    };
    // `-rw-r--r--  1 me  staff  …`: the names OpenSSH puts in a listing.
    if let Some(longname) = longname {
        let mut fields = longname.split_whitespace();
        if fields.next().and_then(mode_of_text).is_some() {
            let _links = fields.next();
            if meta.owner.is_empty() {
                meta.owner = fields.next().unwrap_or_default().to_string();
            }
            if meta.group.is_empty() {
                meta.group = fields.next().unwrap_or_default().to_string();
            }
        }
    }
    meta
}

// ─── Connecting ───

/// The client's side of the SSH handshake: the host key check.
struct Client {
    server: String,
    host: String,
    port: u16,
    credentials: Arc<Mutex<Credentials>>,
    /// Why the host key was refused, for the error.
    refusal: Arc<Mutex<Option<VfsError>>>,
    prompting: Arc<AtomicBool>,
    closed: Arc<AtomicBool>,
    /// Told when the connection ends; dropped with the session, it tells
    /// that too.
    gone: watch::Sender<bool>,
    notifier: Notifier,
}

impl client::Handler for Client {
    type Error = russh::Error;

    async fn check_server_key(&mut self, offered: &PublicKeyOrCertificate) -> Result<bool, Self::Error> {
        let key = match offered {
            PublicKeyOrCertificate::PublicKey { key, .. } => key.clone(),
            PublicKeyOrCertificate::Certificate(certificate) => {
                PublicKey::new(certificate.public_key().clone(), "")
            }
        };
        let trusted = self.credentials.lock().host_key.clone();
        if let Some(trusted) = trusted {
            if trusted.key_data() == key.key_data() {
                return Ok(true);
            }
            *self.refusal.lock() = Some(changed_key(&self.host, None));
            return Ok(false);
        }
        let (host, port) = (self.host.clone(), self.port);
        let check = {
            let key = key.clone();
            tokio::task::spawn_blocking(move || known_hosts::check(&host, port, &key))
                .await
                .unwrap_or(HostKeyCheck::Unknown)
        };
        match check {
            HostKeyCheck::Known => {}
            HostKeyCheck::Changed { file, line } => {
                *self.refusal.lock() = Some(changed_key(&self.host, Some((&file, line))));
                return Ok(false);
            }
            HostKeyCheck::Revoked { file, line } => {
                // Revoked is refused as a changed key is: the file says why.
                *self.refusal.lock() = Some(changed_key(&self.host, Some((&file, line))));
                return Ok(false);
            }
            HostKeyCheck::Unknown => {
                self.prompting.store(true, Ordering::SeqCst);
                let answer = prompt::ask(Question::HostKey {
                    server: self.server.clone(),
                    host: self.host.clone(),
                    port: self.port,
                    algorithm: known_hosts::key_type(&key),
                    fingerprint: known_hosts::fingerprint(&key),
                })
                .await;
                self.prompting.store(false, Ordering::SeqCst);
                if !answer.accept {
                    *self.refusal.lock() =
                        Some(VfsError::new(VfsErrorKind::HostKeyUnknown, None, self.host.clone()));
                    return Ok(false);
                }
                if answer.remember {
                    let (host, port, remembered) = (self.host.clone(), self.port, key.clone());
                    // Not kept on disk is no reason to stop: it stays
                    // trusted for this run.
                    let _ =
                        tokio::task::spawn_blocking(move || known_hosts::remember(&host, port, &remembered))
                            .await;
                }
            }
        }
        self.credentials.lock().host_key = Some(key);
        Ok(true)
    }

    async fn disconnected(
        &mut self,
        _reason: client::DisconnectReason<Self::Error>,
    ) -> Result<(), Self::Error> {
        if !self.closed.swap(true, Ordering::SeqCst) {
            self.notifier.lost();
        }
        self.gone.send_replace(true);
        Ok(())
    }
}

/// The host's key is not the one on record: the message names where the
/// record is (`~/.ssh/known_hosts:12`), else the host (a key trusted this
/// run and then another shown).
fn changed_key(host: &str, at: Option<(&Path, usize)>) -> VfsError {
    let message = match at {
        Some((file, line)) => format!("{}:{line}", file.display()),
        None => host.to_string(),
    };
    VfsError::new(VfsErrorKind::HostKeyChanged, None, message)
}

/// Connects, checks the host key, logs in and starts SFTP; the handshake
/// may wait on the user's answers without its deadline running out.
async fn open_link(
    spec: &ConnectSpec,
    credentials: Arc<Mutex<Credentials>>,
    notifier: Notifier,
) -> VfsResult<Link> {
    let prompting = Arc::new(AtomicBool::new(false));
    let attempt = connect_and_log_in(spec, credentials, notifier, prompting.clone());
    patient_deadline(attempt, prompting, CONNECT_TIMEOUT).await
}

/// `work`, failed with [`VfsErrorKind::TimedOut`] once it has made no
/// progress for `limit` while not waiting on the user.
async fn patient_deadline<T>(
    work: impl Future<Output = VfsResult<T>>,
    prompting: Arc<AtomicBool>,
    limit: Duration,
) -> VfsResult<T> {
    tokio::pin!(work);
    let mut deadline = tokio::time::Instant::now() + limit;
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    loop {
        tokio::select! {
            result = &mut work => return result,
            _ = tick.tick() => {
                let now = tokio::time::Instant::now();
                if prompting.load(Ordering::SeqCst) {
                    deadline = now + limit;
                } else if now >= deadline {
                    return Err(timed_out());
                }
            }
        }
    }
}

async fn connect_and_log_in(
    spec: &ConnectSpec,
    credentials: Arc<Mutex<Credentials>>,
    notifier: Notifier,
    prompting: Arc<AtomicBool>,
) -> VfsResult<Link> {
    for _ in 0..LOGIN_ROUNDS {
        if let Some(link) =
            connect_once(spec, credentials.clone(), notifier.clone(), prompting.clone()).await?
        {
            return Ok(link);
        }
    }
    Err(VfsError::new(VfsErrorKind::AuthFailed, None, spec.address.display_root()))
}

/// One connection and login; `None` when a password was refused and the
/// server takes no other on this connection.
async fn connect_once(
    spec: &ConnectSpec,
    credentials: Arc<Mutex<Credentials>>,
    notifier: Notifier,
    prompting: Arc<AtomicBool>,
) -> VfsResult<Option<Link>> {
    let address = &spec.address;
    let socket = tokio::net::TcpStream::connect((address.host.as_str(), address.port))
        .await
        .map_err(|e| unreachable_error(&e, address))?;
    let _ = socket.set_nodelay(true);
    let config = Arc::new(client::Config {
        keepalive_interval: Some(KEEPALIVE),
        keepalive_max: 3,
        inactivity_timeout: None,
        nodelay: true,
        ..Default::default()
    });
    let refusal = Arc::new(Mutex::new(None));
    let closed = Arc::new(AtomicBool::new(false));
    let (gone, gone_seen) = watch::channel(false);
    let client = Client {
        server: address.key(),
        host: address.host.clone(),
        port: address.port,
        credentials: credentials.clone(),
        refusal: refusal.clone(),
        prompting: prompting.clone(),
        closed: closed.clone(),
        gone,
        notifier,
    };
    let mut handle = match client::connect_stream(config, socket, client).await {
        Ok(handle) => handle,
        Err(error) => return Err(refusal.lock().take().unwrap_or_else(|| ssh_error(error))),
    };
    let mut login = Login {
        handle: &mut handle,
        user: if address.user.is_empty() { crate::system::user_name() } else { address.user.clone() },
        server: address.key(),
        spec,
        credentials: &credentials,
        prompting: &prompting,
        methods: Vec::new(),
        keychain_tried: false,
        refused_here: false,
    };
    if !login.run().await? {
        closed.store(true, Ordering::SeqCst);
        let _ = handle.disconnect(russh::Disconnect::ByApplication, "", "en").await;
        return Ok(None);
    }
    let channel = handle.channel_open_session().await.map_err(ssh_error)?;
    channel.request_subsystem(true, "sftp").await.map_err(ssh_error)?;
    let config =
        russh_sftp::client::Config { request_timeout_secs: REQUEST_TIMEOUT.as_secs(), ..Default::default() };
    let sftp = RawSftpSession::new_with_config(channel.into_stream(), config);
    sftp.init().await.map_err(|e| sftp_error(e, None))?;
    Ok(Some(Link { handle, sftp: Arc::new(sftp), closed, gone: gone_seen }))
}

/// Where a password came from, so a refused one is not offered again and
/// an accepted one is kept as the user asked.
enum Source {
    Kept,
    Keychain,
    User { remember: bool },
}

/// Logging in, one way after another as the server allows them.
struct Login<'a> {
    handle: &'a mut Handle<Client>,
    user: String,
    server: String,
    spec: &'a ConnectSpec,
    credentials: &'a Mutex<Credentials>,
    prompting: &'a AtomicBool,
    /// What the server still offers.
    methods: Vec<MethodKind>,
    keychain_tried: bool,
    /// A password was refused on this connection.
    refused_here: bool,
}

impl Login<'_> {
    /// Logs in; `false` when a password was refused and only a new
    /// connection can take another.
    async fn run(&mut self) -> VfsResult<bool> {
        // A "none" attempt answers with the ways the server takes.
        match self.handle.authenticate_none(self.user.clone()).await.map_err(ssh_error)? {
            AuthResult::Success => return Ok(true),
            AuthResult::Failure { remaining_methods, .. } => self.methods = remaining_methods.to_vec(),
        }
        let done = match &self.spec.auth {
            AuthMethod::Agent => self.agent().await?,
            AuthMethod::Key(path) => {
                let paths = match path {
                    Some(path) => vec![path.clone()],
                    None => default_keys(),
                };
                self.keys(paths).await?
            }
            AuthMethod::Password => self.keyboard().await? || self.password().await?,
            AuthMethod::Auto => {
                self.agent().await?
                    || self.keys(default_keys()).await?
                    || self.keyboard().await?
                    || self.password().await?
            }
        };
        if done {
            Ok(true)
        } else if self.refused_here {
            Ok(false)
        } else {
            Err(VfsError::new(
                VfsErrorKind::AuthFailed,
                None,
                format!("{}@{}", self.user, self.spec.address.host),
            ))
        }
    }

    fn offers(&self, kind: MethodKind) -> bool {
        self.methods.contains(&kind)
    }

    /// Takes in what a failed attempt says: the ways left.
    fn failed(&mut self, remaining: &[MethodKind]) {
        self.methods = remaining.to_vec();
    }

    async fn ask(&self, question: Question) -> Answer {
        self.prompting.store(true, Ordering::SeqCst);
        let answer = prompt::ask(question).await;
        self.prompting.store(false, Ordering::SeqCst);
        answer
    }

    async fn agent(&mut self) -> VfsResult<bool> {
        if !self.offers(MethodKind::PublicKey) {
            return Ok(false);
        }
        #[cfg(unix)]
        let agent = russh::keys::agent::client::AgentClient::connect_env().await.ok().map(|a| a.dynamic());
        #[cfg(windows)]
        let agent =
            russh::keys::agent::client::AgentClient::connect_named_pipe(r"\\.\pipe\openssh-ssh-agent")
                .await
                .ok()
                .map(|a| a.dynamic());
        #[cfg(not(any(unix, windows)))]
        let agent: Option<
            russh::keys::agent::client::AgentClient<
                Box<dyn russh::keys::agent::client::AgentStream + Send + Unpin>,
            >,
        > = None;
        let Some(mut agent) = agent else { return Ok(false) };
        let Ok(identities) = agent.request_identities().await else { return Ok(false) };
        for identity in identities {
            let russh::keys::agent::AgentIdentity::PublicKey { key, .. } = identity else { continue };
            if !self.offers(MethodKind::PublicKey) {
                break;
            }
            let hash = self.rsa_hash(key.algorithm().is_rsa()).await?;
            match self.handle.authenticate_publickey_with(self.user.clone(), key, hash, &mut agent).await {
                Ok(AuthResult::Success) => return Ok(true),
                Ok(AuthResult::Failure { remaining_methods, .. }) => self.failed(&remaining_methods),
                Err(_) => continue,
            }
        }
        Ok(false)
    }

    async fn rsa_hash(&mut self, rsa: bool) -> VfsResult<Option<russh::keys::HashAlg>> {
        if !rsa {
            return Ok(None);
        }
        Ok(self.handle.best_supported_rsa_hash().await.map_err(ssh_error)?.flatten())
    }

    async fn keys(&mut self, paths: Vec<PathBuf>) -> VfsResult<bool> {
        for path in paths {
            if !self.offers(MethodKind::PublicKey) {
                break;
            }
            let Some(key) = self.load_key(&path).await? else { continue };
            let hash = self.rsa_hash(key.algorithm().is_rsa()).await?;
            let key = PrivateKeyWithHashAlg::new(Arc::new(key), hash);
            match self.handle.authenticate_publickey(self.user.clone(), key).await.map_err(ssh_error)? {
                AuthResult::Success => return Ok(true),
                AuthResult::Failure { remaining_methods, .. } => self.failed(&remaining_methods),
            }
        }
        Ok(false)
    }

    /// The private key at `path`, its passphrase asked for when it is
    /// encrypted; `None` when it cannot be read or the user gave up.
    async fn load_key(&mut self, path: &Path) -> VfsResult<Option<PrivateKey>> {
        match load(path.to_path_buf(), None).await {
            Ok(key) => return Ok(Some(key)),
            Err(russh::keys::Error::KeyIsEncrypted) => {}
            Err(_) => return Ok(None),
        }
        let shown = path.to_string_lossy().into_owned();
        let account = secrets::passphrase_account(&shown);
        let kept = self.credentials.lock().passphrases.get(path).cloned();
        let mut candidates: Vec<(String, Option<bool>)> = Vec::new();
        if let Some(kept) = kept {
            candidates.push((kept, None));
        } else if let Some(stored) = secrets::get_async(account.clone()).await {
            candidates.push((stored, None));
        }
        let mut retry = false;
        for _ in 0..4 {
            let (passphrase, remember) = match candidates.pop() {
                Some(candidate) => candidate,
                None => {
                    let answer = self
                        .ask(Question::Passphrase {
                            server: self.server.clone(),
                            key_path: shown.clone(),
                            retry,
                        })
                        .await;
                    match (answer.accept, answer.text()) {
                        (true, Some(text)) => (text.to_string(), Some(answer.remember)),
                        _ => return Ok(None),
                    }
                }
            };
            match load(path.to_path_buf(), Some(passphrase.clone())).await {
                Ok(key) => {
                    self.credentials.lock().passphrases.insert(path.to_path_buf(), passphrase.clone());
                    if remember == Some(true) {
                        let _ = secrets::set_async(account, passphrase).await;
                    }
                    return Ok(Some(key));
                }
                Err(_) => retry = true,
            }
        }
        Ok(None)
    }

    /// The server's own prompts; one hidden prompt is taken for the
    /// password, and asked as one.
    async fn keyboard(&mut self) -> VfsResult<bool> {
        if !self.offers(MethodKind::KeyboardInteractive) {
            return Ok(false);
        }
        let mut response = self
            .handle
            .authenticate_keyboard_interactive_start(self.user.clone(), None)
            .await
            .map_err(ssh_error)?;
        // The password given to a prompt, and that prompt's words.
        let mut password: Option<(String, Source, String)> = None;
        // Whether the password was taken (a one-time code may follow).
        let mut password_through = false;
        let mut rounds = 0;
        loop {
            rounds += 1;
            match response {
                KeyboardInteractiveAuthResponse::Success => {
                    if let Some((text, source, _)) = password {
                        self.password_accepted(text, source).await;
                    }
                    return Ok(true);
                }
                KeyboardInteractiveAuthResponse::Failure { remaining_methods, .. } => {
                    self.failed(&remaining_methods);
                    if let Some((_, source, _)) = &password {
                        if !password_through {
                            self.password_refused(source);
                        }
                    }
                    return Ok(false);
                }
                KeyboardInteractiveAuthResponse::InfoRequest { name, instructions, prompts } => {
                    if rounds > 8 {
                        return Ok(false);
                    }
                    let hidden_one = prompts.len() == 1 && !prompts[0].echo;
                    let asked_again = !prompts.is_empty()
                        && password.as_ref().is_some_and(|(_, _, words)| *words == prompts[0].prompt);
                    if password.is_some() && !asked_again {
                        password_through = true;
                    }
                    let answers = if prompts.is_empty() {
                        Vec::new()
                    } else if hidden_one && (password.is_none() || asked_again) {
                        // A password prompt (PAM's "Password:"), asked as
                        // a password; the same prompt again means the one
                        // given was refused.
                        if let Some((_, source, _)) = password.take() {
                            self.password_refused(&source);
                        }
                        let (text, source) = self.next_password(false).await?;
                        password = Some((text.clone(), source, prompts[0].prompt.clone()));
                        vec![text]
                    } else {
                        let answer = self
                            .ask(Question::KeyboardInteractive {
                                server: self.server.clone(),
                                name,
                                instructions,
                                prompts: prompts.iter().map(|p| (p.prompt.clone(), p.echo)).collect(),
                            })
                            .await;
                        if !answer.accept {
                            return Err(VfsError::cancelled());
                        }
                        let mut texts = answer.texts;
                        texts.resize(prompts.len(), String::new());
                        texts
                    };
                    response = self
                        .handle
                        .authenticate_keyboard_interactive_respond(answers)
                        .await
                        .map_err(ssh_error)?;
                }
            }
        }
    }

    async fn password(&mut self) -> VfsResult<bool> {
        for _ in 0..4 {
            if !self.offers(MethodKind::Password) {
                return Ok(false);
            }
            let (text, source) = self.next_password(false).await?;
            match self
                .handle
                .authenticate_password(self.user.clone(), text.clone())
                .await
                .map_err(ssh_error)?
            {
                AuthResult::Success => {
                    self.password_accepted(text, source).await;
                    return Ok(true);
                }
                AuthResult::Failure { remaining_methods, .. } => {
                    self.failed(&remaining_methods);
                    self.password_refused(&source);
                }
            }
        }
        Ok(false)
    }

    /// A password was refused: it is not offered again, and the next one
    /// asked for says so. (Some servers take no second password on the
    /// connection: [`Login::run`] then opens another.)
    fn password_refused(&mut self, source: &Source) {
        self.refused_here = true;
        let mut credentials = self.credentials.lock();
        credentials.password_refused = true;
        match source {
            Source::Kept => credentials.password = None,
            Source::Keychain => credentials.keychain_failed = true,
            Source::User { .. } => {}
        }
    }

    /// The password to try: the one kept, the keychain's, else the user's
    /// (told the last one was wrong when one was refused, here or on an
    /// earlier connection).
    async fn next_password(&mut self, retry: bool) -> VfsResult<(String, Source)> {
        let retry = retry || self.credentials.lock().password_refused;
        if !retry {
            let kept = self.credentials.lock().password.clone();
            if let Some(kept) = kept {
                return Ok((kept, Source::Kept));
            }
            let keychain_failed = self.credentials.lock().keychain_failed;
            if !self.keychain_tried && !keychain_failed {
                self.keychain_tried = true;
                if let Some(stored) = secrets::get_async(self.server.clone()).await {
                    return Ok((stored, Source::Keychain));
                }
            }
        }
        let answer = self
            .ask(Question::Password { server: self.server.clone(), user: self.user.clone(), retry })
            .await;
        match (answer.accept, answer.text()) {
            (true, Some(text)) => Ok((text.to_string(), Source::User { remember: answer.remember })),
            _ => Err(VfsError::cancelled()),
        }
    }

    async fn password_accepted(&mut self, text: String, source: Source) {
        {
            let mut credentials = self.credentials.lock();
            credentials.password = Some(text.clone());
            credentials.password_refused = false;
        }
        if let Source::User { remember } = source {
            if remember {
                let _ = secrets::set_async(self.server.clone(), text).await;
            } else if self.credentials.lock().keychain_failed {
                // The keychain's one is wrong and the user did not ask to
                // keep the new one: forget it.
                let _ = secrets::delete_async(self.server.clone()).await;
            }
        }
    }
}

/// `~/.ssh/id_ed25519`, `id_ecdsa`, `id_rsa`: those there are.
fn default_keys() -> Vec<PathBuf> {
    let ssh = crate::system::home_dir().join(".ssh");
    ["id_ed25519", "id_ecdsa", "id_rsa"]
        .iter()
        .map(|name| ssh.join(name))
        .filter(|path| path.is_file())
        .collect()
}

/// Reads and decrypts a key file off the runtime's workers (decryption
/// takes a while by design).
async fn load(path: PathBuf, passphrase: Option<String>) -> Result<PrivateKey, russh::keys::Error> {
    tokio::task::spawn_blocking(move || russh::keys::load_secret_key(&path, passphrase.as_deref()))
        .await
        .unwrap_or(Err(russh::keys::Error::CouldNotReadKey))
}

// ─── Errors ───

/// The connection ended; its kind says it all.
fn lost() -> VfsError {
    VfsError::new(VfsErrorKind::ConnectionLost, None, String::new())
}

/// A failure to reach the server at all.
pub(crate) fn unreachable_error(error: &std::io::Error, address: &ServerAddress) -> VfsError {
    use std::io::ErrorKind;
    let kind = match error.kind() {
        ErrorKind::TimedOut => VfsErrorKind::TimedOut,
        _ => VfsErrorKind::HostUnreachable,
    };
    VfsError::new(kind, None, format!("{}:{}: {error}", address.host, address.port))
}

fn ssh_error(error: russh::Error) -> VfsError {
    use russh::Error as E;
    let kind = match &error {
        E::IO(_) | E::Disconnect | E::HUP | E::RecvError | E::SendError | E::ChannelOpenFailure(_) => {
            VfsErrorKind::ConnectionLost
        }
        E::ConnectionTimeout | E::KeepaliveTimeout | E::InactivityTimeout | E::Elapsed(_) => {
            VfsErrorKind::TimedOut
        }
        E::UnknownKey => VfsErrorKind::HostKeyUnknown,
        E::NotAuthenticated | E::NoAuthMethod => VfsErrorKind::AuthFailed,
        _ => VfsErrorKind::Io,
    };
    VfsError::new(kind, None, format!("SSH: {error}"))
}

fn sftp_error(error: SftpError, path: Option<&str>) -> VfsError {
    let (kind, message) = match &error {
        SftpError::Status(status) => {
            let kind = match status.status_code {
                StatusCode::NoSuchFile => VfsErrorKind::NotFound,
                StatusCode::PermissionDenied => VfsErrorKind::PermissionDenied,
                StatusCode::OpUnsupported => VfsErrorKind::Unsupported,
                StatusCode::NoConnection | StatusCode::ConnectionLost => VfsErrorKind::ConnectionLost,
                _ => VfsErrorKind::Io,
            };
            let said = if status.error_message.is_empty() {
                status.status_code.to_string()
            } else {
                status.error_message.clone()
            };
            (kind, said)
        }
        SftpError::Timeout => (VfsErrorKind::TimedOut, "the server did not answer in time".to_string()),
        SftpError::IO(_) | SftpError::UnexpectedBehavior(_) => {
            (VfsErrorKind::ConnectionLost, error.to_string())
        }
        SftpError::Limited(_) | SftpError::UnexpectedPacket => (VfsErrorKind::Io, error.to_string()),
    };
    let message = match path {
        Some(path) => format!("{path}: {message}"),
        None => message,
    };
    VfsError::remote(kind, path, message)
}
