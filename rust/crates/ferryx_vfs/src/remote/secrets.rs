//! Passwords and passphrases the user asked to remember, in the system's
//! keychain: the macOS Keychain, the Windows Credential Manager, the
//! Secret Service (GNOME Keyring, KWallet) on Linux. Never in the
//! preferences, never in a log. Kept under the service `Ferryx`, by the
//! server's key (`sftp://me@host:22`) or `passphrase:<key file>`.
//!
//! A keychain may block (it can ask the user to unlock it) and its Linux
//! client runs a runtime of its own, so it is reached from a thread of its
//! own, never from the network runtime's.

use std::collections::HashMap;
use std::sync::{Arc, LazyLock};

use parking_lot::{Mutex, RwLock};

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// The keychain's service name for every Ferryx item.
pub const SERVICE: &str = "Ferryx";

/// Where secrets are kept.
pub trait SecretStore: Send + Sync {
    /// The secret kept for `account`; `None` when there is none or the
    /// keychain cannot be read.
    fn get(&self, account: &str) -> Option<String>;
    fn set(&self, account: &str, secret: &str) -> VfsResult<()>;
    /// Forgets `account`'s secret; nothing to forget is no error.
    fn delete(&self, account: &str) -> VfsResult<()>;
}

/// The system's keychain.
pub struct KeyringStore;

impl SecretStore for KeyringStore {
    fn get(&self, account: &str) -> Option<String> {
        keyring::Entry::new(SERVICE, account).ok()?.get_password().ok()
    }

    fn set(&self, account: &str, secret: &str) -> VfsResult<()> {
        let entry = keyring::Entry::new(SERVICE, account).map_err(keychain_error)?;
        entry.set_password(secret).map_err(keychain_error)
    }

    fn delete(&self, account: &str) -> VfsResult<()> {
        let entry = keyring::Entry::new(SERVICE, account).map_err(keychain_error)?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(keychain_error(e)),
        }
    }
}

/// The keychain's own words, without the secret (its errors never carry
/// one).
fn keychain_error(error: keyring::Error) -> VfsError {
    let kind = match error {
        keyring::Error::NoStorageAccess(_) => VfsErrorKind::PermissionDenied,
        _ => VfsErrorKind::Io,
    };
    VfsError::new(kind, None, format!("the keychain: {error}"))
}

/// Secrets in memory, for the tests (and a desktop without a keychain).
#[derive(Default)]
pub struct MemoryStore {
    secrets: Mutex<HashMap<String, String>>,
}

impl SecretStore for MemoryStore {
    fn get(&self, account: &str) -> Option<String> {
        self.secrets.lock().get(account).cloned()
    }

    fn set(&self, account: &str, secret: &str) -> VfsResult<()> {
        self.secrets.lock().insert(account.to_string(), secret.to_string());
        Ok(())
    }

    fn delete(&self, account: &str) -> VfsResult<()> {
        self.secrets.lock().remove(account);
        Ok(())
    }
}

static STORE: LazyLock<RwLock<Arc<dyn SecretStore>>> = LazyLock::new(|| RwLock::new(Arc::new(KeyringStore)));

/// The store in use: the system's keychain unless [`use_store`] said
/// otherwise.
pub fn store() -> Arc<dyn SecretStore> {
    STORE.read().clone()
}

/// Puts `store` in place of the keychain (the tests keep their secrets in
/// memory).
pub fn use_store(store: Arc<dyn SecretStore>) {
    *STORE.write() = store;
}

/// The account a key file's passphrase is kept under.
pub fn passphrase_account(key_path: &str) -> String {
    format!("passphrase:{key_path}")
}

/// [`SecretStore::get`] from inside the runtime: on a thread of its own.
pub async fn get_async(account: String) -> Option<String> {
    off_runtime(move || store().get(&account)).await.flatten()
}

/// [`SecretStore::set`] from inside the runtime.
pub async fn set_async(account: String, secret: String) -> VfsResult<()> {
    off_runtime(move || store().set(&account, &secret))
        .await
        .unwrap_or_else(|| Err(VfsError::new(VfsErrorKind::Io, None, "the keychain did not answer")))
}

/// [`SecretStore::delete`] from inside the runtime.
pub async fn delete_async(account: String) -> VfsResult<()> {
    off_runtime(move || store().delete(&account))
        .await
        .unwrap_or_else(|| Err(VfsError::new(VfsErrorKind::Io, None, "the keychain did not answer")))
}

async fn off_runtime<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Option<T> {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let spawned = std::thread::Builder::new().name("ferryx-keychain".into()).spawn(move || {
        let _ = sender.send(work());
    });
    if spawned.is_err() {
        return None;
    }
    receiver.await.ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_keeps_and_forgets() {
        let store = MemoryStore::default();
        assert_eq!(store.get("a"), None);
        store.set("a", "x").unwrap();
        assert_eq!(store.get("a").as_deref(), Some("x"));
        store.delete("a").unwrap();
        store.delete("a").unwrap();
        assert_eq!(store.get("a"), None);
        assert_eq!(passphrase_account("/k"), "passphrase:/k");
    }
}
