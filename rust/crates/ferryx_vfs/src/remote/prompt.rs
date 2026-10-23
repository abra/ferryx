//! Questions a connection asks the user while it is made: a host key not
//! seen before, a password, a key's passphrase, a server's own prompts
//! (keyboard-interactive). Each goes to the one listener (the bridge, which
//! sends it to the interface as an event) and waits for its answer, given
//! by its id; nobody listening, or the question withdrawn, answers no.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock};

use parking_lot::Mutex;
use tokio::sync::oneshot;

use super::runtime::{self, Stop};

/// What a connection needs to know from the user.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Question {
    /// The server's SSH key is in no known_hosts file: trust it?
    HostKey {
        /// The server's key (see `ServerAddress::key`).
        server: String,
        host: String,
        port: u16,
        /// `ssh-ed25519`, `ecdsa-sha2-nistp256`, `rsa-sha2-512`…
        algorithm: String,
        /// `SHA256:…`, as OpenSSH shows it.
        fingerprint: String,
    },
    /// The server wants a password.
    Password {
        server: String,
        user: String,
        /// The one given before was refused.
        retry: bool,
    },
    /// A private key is encrypted.
    Passphrase { server: String, key_path: String, retry: bool },
    /// The server's own prompts (one-time codes, a PAM password).
    KeyboardInteractive {
        server: String,
        name: String,
        instructions: String,
        /// Each prompt and whether what is typed may show.
        prompts: Vec<(String, bool)>,
    },
}

impl Question {
    pub fn server(&self) -> &str {
        match self {
            Question::HostKey { server, .. }
            | Question::Password { server, .. }
            | Question::Passphrase { server, .. }
            | Question::KeyboardInteractive { server, .. } => server,
        }
    }
}

/// The user's answer.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Answer {
    /// Go on (trust the key, use the text); `false` is Cancel.
    pub accept: bool,
    /// The password, the passphrase, or one text per prompt.
    pub texts: Vec<String>,
    /// Keep the password in the system's keychain; for a host key, keep it
    /// in Ferryx's known_hosts (else trusted for this run only).
    pub remember: bool,
}

impl Answer {
    pub fn text(&self) -> Option<&str> {
        self.texts.first().map(String::as_str)
    }
}

pub type Listener = Arc<dyn Fn(u64, &Question) + Send + Sync>;

/// A question withdrawn: the listener drops its dialog.
pub type Withdrawn = Arc<dyn Fn(u64) + Send + Sync>;

#[derive(Default)]
struct Prompts {
    listener: Option<Listener>,
    withdrawn: Option<Withdrawn>,
    pending: HashMap<u64, (String, oneshot::Sender<Answer>)>,
}

static PROMPTS: LazyLock<Mutex<Prompts>> = LazyLock::new(Default::default);
static NEXT: AtomicU64 = AtomicU64::new(1);

/// The one listener; a later call replaces it.
pub fn set_listener(listener: Option<Listener>, withdrawn: Option<Withdrawn>) {
    let mut prompts = PROMPTS.lock();
    prompts.listener = listener;
    prompts.withdrawn = withdrawn;
}

/// Asks `question` and waits for the answer; a refusal when nobody
/// listens. Dropped before the answer (its connection given up), the
/// question is withdrawn.
pub async fn ask(question: Question) -> Answer {
    let (id, receiver) = match post(&question) {
        Some(posted) => posted,
        None => return Answer::default(),
    };
    let pending = Pending(id);
    let answer = receiver.await.unwrap_or_default();
    std::mem::forget(pending);
    PROMPTS.lock().pending.remove(&id);
    answer
}

/// A question asked and not answered yet: dropped, it is withdrawn.
struct Pending(u64);

impl Drop for Pending {
    fn drop(&mut self) {
        let withdrawn = {
            let mut prompts = PROMPTS.lock();
            prompts.pending.remove(&self.0).and(prompts.withdrawn.clone())
        };
        if let Some(withdrawn) = withdrawn {
            withdrawn(self.0);
        }
    }
}

/// [`ask`] from a thread outside the runtime (an FTP connection).
pub fn ask_blocking(question: Question, stop: Stop) -> Answer {
    runtime::run_unbounded(async { Ok(ask(question).await) }, stop).unwrap_or_default()
}

fn post(question: &Question) -> Option<(u64, oneshot::Receiver<Answer>)> {
    let id = NEXT.fetch_add(1, Ordering::SeqCst);
    let (sender, receiver) = oneshot::channel();
    let listener = {
        let mut prompts = PROMPTS.lock();
        let listener = prompts.listener.clone()?;
        prompts.pending.insert(id, (question.server().to_string(), sender));
        listener
    };
    listener(id, question);
    Some((id, receiver))
}

/// Gives the answer to the question `id`; an answer to a question no
/// longer asked is dropped.
pub fn answer(id: u64, answer: Answer) {
    if let Some((_, sender)) = PROMPTS.lock().pending.remove(&id) {
        let _ = sender.send(answer);
    }
}

/// Withdraws every question about `server` (its connection was given up):
/// each is refused, and the listener told.
pub fn withdraw(server: &str) {
    let (ids, withdrawn) = {
        let mut prompts = PROMPTS.lock();
        let ids: Vec<u64> =
            prompts.pending.iter().filter(|(_, (s, _))| s == server).map(|(id, _)| *id).collect();
        for id in &ids {
            if let Some((_, sender)) = prompts.pending.remove(id) {
                let _ = sender.send(Answer::default());
            }
        }
        (ids, prompts.withdrawn.clone())
    };
    if let Some(withdrawn) = withdrawn {
        for id in ids {
            withdrawn(id);
        }
    }
}

/// The questions waiting, for the tests.
pub fn pending() -> Vec<u64> {
    let mut ids: Vec<u64> = PROMPTS.lock().pending.keys().copied().collect();
    ids.sort_unstable();
    ids
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicBool;

    use super::*;

    #[test]
    fn nobody_listening_is_a_no_and_an_answer_reaches_its_question() {
        set_listener(None, None);
        assert!(
            !ask_blocking(
                Question::Password { server: "s".into(), user: "u".into(), retry: false },
                &runtime::never
            )
            .accept
        );

        set_listener(
            Some(Arc::new(|id, question| {
                if let Question::Password { .. } = question {
                    std::thread::spawn(move || {
                        answer(id, Answer { accept: true, texts: vec!["secret".into()], remember: true })
                    });
                }
            })),
            None,
        );
        let got = ask_blocking(
            Question::Password { server: "s".into(), user: "u".into(), retry: false },
            &runtime::never,
        );
        assert!(got.accept);
        assert_eq!(got.text(), Some("secret"));
        assert!(got.remember);

        // Nobody answers; the caller stops waiting and the question is
        // withdrawn.
        let withdrawn = Arc::new(Mutex::new(Vec::new()));
        let seen = withdrawn.clone();
        let asked = Arc::new(AtomicBool::new(false));
        let posted = asked.clone();
        set_listener(
            Some(Arc::new(move |_, _| posted.store(true, Ordering::SeqCst))),
            Some(Arc::new(move |id| seen.lock().push(id))),
        );
        let got =
            ask_blocking(Question::Password { server: "s".into(), user: "u".into(), retry: false }, &|| {
                asked.load(Ordering::SeqCst)
            });
        assert!(!got.accept);
        assert_eq!(withdrawn.lock().len(), 1);
        assert!(pending().is_empty());
        set_listener(None, None);
    }
}
