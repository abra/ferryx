//! What the network tests share: secrets in memory, known_hosts files of
//! their own, the test authority trusted, and the user's answers scripted
//! per server (tests run side by side, each against its own server, so a
//! question is answered by its server's script).

#![allow(dead_code)]

use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Once};

use ferryx_vfs::remote::prompt::{self, Answer, Question};
use ferryx_vfs::remote::{known_hosts, secrets, tls};
use parking_lot::Mutex;

static SETUP: Once = Once::new();
static DIR: LazyLock<tempfile::TempDir> =
    LazyLock::new(|| tempfile::tempdir().expect("a folder for known_hosts"));
static SCRIPTS: LazyLock<Mutex<HashMap<String, VecDeque<Answer>>>> = LazyLock::new(Default::default);
static ASKED: LazyLock<Mutex<Vec<Question>>> = LazyLock::new(Default::default);
pub static STORE: LazyLock<Arc<secrets::MemoryStore>> = LazyLock::new(Default::default);

/// Sets the process up once.
pub fn setup() {
    SETUP.call_once(|| {
        secrets::use_store(STORE.clone());
        known_hosts::use_files(vec![user_known_hosts()], DIR.path().join("ferryx/known_hosts"));
        tls::trust_extra_roots(vec![ferryx_test_servers::ca().root.clone()]);
        prompt::set_listener(
            Some(Arc::new(|id, question: &Question| {
                ASKED.lock().push(question.clone());
                let answer = SCRIPTS
                    .lock()
                    .get_mut(question.server())
                    .and_then(VecDeque::pop_front)
                    .unwrap_or_default();
                prompt::answer(id, answer);
            })),
            None,
        );
    });
}

/// The user's own known_hosts file (read only to Ferryx).
pub fn user_known_hosts() -> PathBuf {
    DIR.path().join("ssh/known_hosts")
}

/// Answers the next questions about `server` as given, in order; a
/// question beyond them is refused.
pub fn script(server: &str, answers: Vec<Answer>) {
    SCRIPTS.lock().insert(server.to_string(), answers.into());
}

/// The questions asked about `server` so far.
pub fn asked(server: &str) -> Vec<Question> {
    ASKED.lock().iter().filter(|q| q.server() == server).cloned().collect()
}

pub fn trust(remember: bool) -> Answer {
    Answer { accept: true, texts: Vec::new(), remember }
}

pub fn text(value: &str, remember: bool) -> Answer {
    Answer { accept: true, texts: vec![value.to_string()], remember }
}

pub fn texts(values: &[&str]) -> Answer {
    Answer { accept: true, texts: values.iter().map(|v| v.to_string()).collect(), remember: false }
}

pub fn cancel() -> Answer {
    Answer::default()
}

/// Fills `dir` with what the listings expect: a file with a name in
/// three scripts, a hidden file, a folder with a file, an empty file.
pub fn sample_tree(dir: &std::path::Path) {
    std::fs::write(dir.join("Привет мир.txt"), "hello").unwrap();
    std::fs::write(dir.join(".hidden"), "h").unwrap();
    std::fs::write(dir.join("empty.bin"), "").unwrap();
    std::fs::write(dir.join("日本語 ü.md"), "# ü").unwrap();
    std::fs::create_dir(dir.join("sub")).unwrap();
    std::fs::write(dir.join("sub/inner.txt"), "inner").unwrap();
}

/// Bytes no two runs of which line up by accident.
pub fn pattern(len: usize) -> Vec<u8> {
    (0..len).map(|i| ((i * 31 + i / 7919) % 251) as u8).collect()
}
