//! The test servers for trying the network locations by hand: SFTP, FTP
//! and WebDAV on 127.0.0.1, each over a folder of a few files, until
//! interrupted (Ctrl+C).
//!
//!     cargo run -p ferryx_test_servers --bin serve
//!
//! Every server takes the user `me` with the password `secret`. The SFTP
//! host key is the tests' first (`keys/host1`), so Ferryx asks once
//! whether to trust it.

use std::fs;
use std::path::Path;

use ferryx_test_servers::dav::{DavOptions, DavServer};
use ferryx_test_servers::ftp::{FtpOptions, FtpServer};
use ferryx_test_servers::sftp::{SftpOptions, SftpServer};

fn fill(root: &Path) {
    fs::create_dir_all(root.join("docs/sub")).expect("folders");
    fs::write(root.join("readme.txt"), "served for Ferryx\n").expect("a file");
    fs::write(root.join("Привет мир.txt"), "привет\n").expect("a file");
    fs::write(root.join("docs/a.md"), "# A\n").expect("a file");
    fs::write(root.join("docs/sub/b.md"), "# B\n").expect("a file");
    fs::write(root.join("big.bin"), vec![7u8; 8 * 1024 * 1024]).expect("a file");
}

fn main() {
    let sftp = SftpServer::start(SftpOptions::default());
    let ftp = FtpServer::start(FtpOptions::default());
    let dav = DavServer::start(DavOptions::default());
    for root in [sftp.root.path(), ftp.root.path(), dav.root.path()] {
        fill(root);
    }
    println!("sftp://me@127.0.0.1:{}/   ({})", sftp.port, sftp.root.path().display());
    println!("ftp://me@127.0.0.1:{}/    ({})", ftp.port, ftp.root.path().display());
    println!("dav://me@127.0.0.1:{}/    ({})", dav.port, dav.root.path().display());
    println!("password: secret; Ctrl+C stops them");
    // The FTP commands as they come, to see what a client does.
    let mut shown = 0;
    loop {
        std::thread::sleep(std::time::Duration::from_millis(200));
        let commands = ftp.commands.lock();
        for command in &commands[shown..] {
            println!("ftp> {command}");
        }
        shown = commands.len();
    }
}
