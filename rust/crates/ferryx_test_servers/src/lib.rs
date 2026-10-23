//! Servers for the network tests, each in the test's own process over a
//! temporary folder: SFTP ([`sftp`], russh's server side with
//! russh-sftp), FTP and FTPS ([`ftp`], a small server of our own, so a
//! test can leave out `MLSD` or cut a transfer short) and WebDAV
//! ([`dav`], dav-server on hyper, optionally behind TLS). Certificates
//! come from a test authority made at start ([`TestCa`]); SSH keys are
//! fixed files in `keys/`.

pub mod dav;
pub mod ftp;
pub mod sftp;

use std::sync::{Arc, LazyLock};

use rcgen::{
    BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, KeyPair, KeyUsagePurpose,
};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};

/// The first test host key (ed25519, OpenSSH format).
pub const HOST_KEY: &str = include_str!("../keys/host1");
/// Another host key: a server that "changed" its key.
pub const OTHER_HOST_KEY: &str = include_str!("../keys/host2");
/// A client key without a passphrase, and its public half.
pub const CLIENT_KEY: &str = include_str!("../keys/client");
pub const CLIENT_KEY_PUB: &str = include_str!("../keys/client.pub");
/// A client key encrypted with [`CLIENT_KEY_PASSPHRASE`].
pub const CLIENT_KEY_ENCRYPTED: &str = include_str!("../keys/client_enc");
pub const CLIENT_KEY_ENCRYPTED_PUB: &str = include_str!("../keys/client_enc.pub");
pub const CLIENT_KEY_PASSPHRASE: &str = "s3cret phrase";

/// A certificate authority for the tests and a server certificate it
/// signed for `localhost` and `127.0.0.1`, valid for a month (the macOS
/// verifier refuses longer lives).
pub struct TestCa {
    pub root: CertificateDer<'static>,
    pub server_config: Arc<rustls::ServerConfig>,
    /// A server certificate signed by nobody the client trusts.
    pub untrusted_config: Arc<rustls::ServerConfig>,
}

static CA: LazyLock<TestCa> = LazyLock::new(make_ca);

/// The tests' authority, made once per process.
pub fn ca() -> &'static TestCa {
    &CA
}

fn make_ca() -> TestCa {
    let provider = Arc::new(rustls::crypto::ring::default_provider());

    let ca_key = KeyPair::generate().expect("a CA key");
    let mut ca_params = CertificateParams::new(Vec::<String>::new()).expect("CA parameters");
    ca_params.distinguished_name.push(DnType::CommonName, "Ferryx Test CA");
    ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    ca_params.key_usages =
        vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign, KeyUsagePurpose::DigitalSignature];
    validity(&mut ca_params);
    let ca_cert = ca_params.self_signed(&ca_key).expect("a CA certificate");

    let server = |signer: Option<(&rcgen::Certificate, &KeyPair)>| {
        let key = KeyPair::generate().expect("a server key");
        let mut params = CertificateParams::new(vec!["localhost".to_string(), "127.0.0.1".to_string()])
            .expect("server parameters");
        params.distinguished_name.push(DnType::CommonName, "localhost");
        params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
        params.key_usages = vec![KeyUsagePurpose::DigitalSignature, KeyUsagePurpose::KeyEncipherment];
        validity(&mut params);
        let cert = match signer {
            Some((issuer, issuer_key)) => {
                params.signed_by(&key, issuer, issuer_key).expect("a signed certificate")
            }
            None => params.self_signed(&key).expect("a self-signed certificate"),
        };
        let chain = vec![cert.der().clone()];
        let private = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key.serialize_der()));
        let config = rustls::ServerConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions()
            .expect("TLS versions")
            .with_no_client_auth()
            .with_single_cert(chain, private)
            .expect("a server configuration");
        Arc::new(config)
    };
    TestCa {
        root: ca_cert.der().clone(),
        server_config: server(Some((&ca_cert, &ca_key))),
        untrusted_config: server(None),
    }
}

/// The day `days` from today, as rcgen takes a date.
fn day(days: i64) -> (i32, u8, u8) {
    use chrono::Datelike;
    let date = chrono::Utc::now().date_naive() + chrono::Duration::days(days);
    (date.year(), date.month() as u8, date.day() as u8)
}

fn validity(params: &mut CertificateParams) {
    let (y, m, d) = day(-1);
    params.not_before = rcgen::date_time_ymd(y, m, d);
    let (y, m, d) = day(30);
    params.not_after = rcgen::date_time_ymd(y, m, d);
}

/// A runtime of the servers' own, on a thread apart from the client's.
pub(crate) fn server_runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("test-server")
            .enable_all()
            .build()
            .expect("the servers' runtime")
    });
    &RUNTIME
}
