//! TLS for FTPS and WebDAV over HTTPS: rustls on `ring`, certificates
//! checked by the desktop itself (Security.framework on macOS, the
//! Windows certificate store, the system's roots on Linux), as a browser
//! there would: a certificate the system does not trust is refused, with
//! no way around it in the interface.

use std::sync::{Arc, LazyLock};

use parking_lot::RwLock;
use rustls::pki_types::CertificateDer;
use rustls::ClientConfig;

use crate::error::{VfsError, VfsErrorKind, VfsResult};

#[derive(Default)]
struct Trust {
    /// Roots trusted beside the system's: the tests' own authority.
    extra: Vec<CertificateDer<'static>>,
    config: Option<Arc<ClientConfig>>,
}

static TRUST: LazyLock<RwLock<Trust>> = LazyLock::new(Default::default);

/// The client configuration every TLS connection uses (one, so FTPS data
/// connections resume the control connection's session, as servers that
/// ask for it require).
pub fn client_config() -> VfsResult<Arc<ClientConfig>> {
    if let Some(config) = TRUST.read().config.clone() {
        return Ok(config);
    }
    let mut trust = TRUST.write();
    if let Some(config) = trust.config.clone() {
        return Ok(config);
    }
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let verifier = if trust.extra.is_empty() {
        rustls_platform_verifier::Verifier::new(provider.clone())
    } else {
        rustls_platform_verifier::Verifier::new_with_extra_roots(trust.extra.clone(), provider.clone())
    }
    .map_err(tls_error)?;
    let config = ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(tls_error)?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(verifier))
        .with_no_client_auth();
    let config = Arc::new(config);
    trust.config = Some(config.clone());
    Ok(config)
}

/// Trusts `roots` beside the system's (the tests' certificate authority).
pub fn trust_extra_roots(roots: Vec<CertificateDer<'static>>) {
    let mut trust = TRUST.write();
    trust.extra = roots;
    trust.config = None;
}

fn tls_error(error: rustls::Error) -> VfsError {
    VfsError::new(VfsErrorKind::Io, None, format!("TLS: {error}"))
}

/// Whether `error` (or what caused it) is a certificate the system does
/// not trust.
pub fn is_certificate_error(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut current: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(e) = current {
        if let Some(tls) = e.downcast_ref::<rustls::Error>() {
            return matches!(tls, rustls::Error::InvalidCertificate(_));
        }
        if let Some(io) = e.downcast_ref::<std::io::Error>() {
            if let Some(inner) = io.get_ref() {
                if is_certificate_error(inner) {
                    return true;
                }
            }
        }
        current = e.source();
    }
    false
}

/// Words a TLS failure for the user, naming the certificate's problem.
pub fn certificate_message(error: &(dyn std::error::Error + 'static)) -> String {
    let mut current: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(e) = current {
        if let Some(rustls::Error::InvalidCertificate(why)) = e.downcast_ref::<rustls::Error>() {
            return format!("the server's certificate is not trusted: {why:?}");
        }
        if let Some(io) = e.downcast_ref::<std::io::Error>() {
            if let Some(inner) = io.get_ref() {
                return certificate_message(inner);
            }
        }
        current = e.source();
    }
    format!("the server's certificate is not trusted: {error}")
}
