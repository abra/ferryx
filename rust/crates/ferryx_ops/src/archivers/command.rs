use std::ffi::OsString;
use std::path::Path;
use std::process::Command;

use super::{Engine, Options, Tool};

/// Names are always literal operands, never shell fragments or option switches.
pub fn create(
    tool: &Tool,
    format: &str,
    output: &Path,
    sources: &[OsString],
    password: bool,
    options: &Options,
) -> Command {
    let mut command = Command::new(&tool.path);
    match tool.engine {
        Engine::SevenZip => {
            command.args(["a", "-y", "-bd", "-bso0", "-bse2", "-bsp0", "-spd", "-sccUTF-8"]);
            command.arg(format!("-t{format}"));
            if password {
                command.arg("-p");
                if format == "7z" {
                    command.arg("-mhe=on");
                }
                if format == "zip" {
                    command.arg("-mem=AES256");
                }
            }
            configure(&mut command, tool.engine, format, options);
            command.arg("--").arg(output).args(sources);
        }
        Engine::Tar | Engine::BsdTar => {
            configure(&mut command, tool.engine, format, options);
            command.args(["-c", "-a", "-f"]).arg(output).arg("--").args(sources);
        }
        Engine::Zip => {
            configure(&mut command, tool.engine, format, options);
            command.args(["-r", "-q"]).arg(output).arg("--").args(sources);
        }
        Engine::Rar => {
            configure(&mut command, tool.engine, format, options);
            command.args(["a", "-idq", "-y"]).arg("--").arg(output).args(sources);
        }
        _ => unreachable!("creation capability checked before command construction"),
    }
    command
}

pub fn extract(tool: &Tool, archive: &Path, options: &Options) -> Command {
    let mut command = Command::new(&tool.path);
    match tool.engine {
        Engine::SevenZip => {
            command.args(["x", "-y", "-bd", "-bso0", "-bse2", "-bsp0", "-spd", "-sccUTF-8"]);
            // For reading, bare -p means an empty password. Omitting it
            // lets the password callback read the supplied stdin instead.
            command.arg("--").arg(archive);
        }
        Engine::Tar | Engine::BsdTar => {
            command.args(["-x", "-f"]).arg(archive);
        }
        Engine::Unzip => {
            command.args(&options.arguments);
            command.args(["-o", "-q"]).arg(archive);
        }
        Engine::Rar | Engine::Unrar => {
            if tool.engine == Engine::Unrar {
                command.args(&options.arguments);
            }
            command.args(["x", "-idq", "-y", "-p-"]).arg("--").arg(archive);
        }
        Engine::Unar => {
            command.args(&options.arguments);
            command.args(["-f", "-D", "-q"]).arg(archive);
        }
        _ => unreachable!("stream compressors use their own adapter"),
    }
    command
}

fn configure(command: &mut Command, engine: Engine, format: &str, options: &Options) {
    if let Some(level) = options.level {
        match engine {
            Engine::SevenZip => {
                command.arg(format!("-mx={level}"));
            }
            Engine::Rar => {
                command.arg(format!("-m{level}"));
            }
            Engine::BsdTar if format != "tar" => {
                command.arg(format!("--options=compression-level={level}"));
            }
            Engine::Zstd => {
                if level > 19 {
                    command.arg("--ultra");
                }
                command.arg(format!("-{level}"));
            }
            Engine::Tar | Engine::BsdTar => {}
            _ => {
                command.arg(format!("-{level}"));
            }
        }
    }
    if let Some(threads) = options.threads {
        match engine {
            Engine::SevenZip => {
                command.arg(format!("-mmt={threads}"));
            }
            Engine::BsdTar if format == "tar.zst" => {
                command.arg(format!("--options=zstd:threads={threads}"));
            }
            Engine::Pigz | Engine::Pbzip2 => {
                command.arg(format!("-p{threads}"));
            }
            Engine::Xz | Engine::Zstd => {
                command.arg(format!("-T{threads}"));
            }
            Engine::Rar => {
                command.arg(format!("-mt{threads}"));
            }
            _ => {}
        }
    }
    if let Some(solid) = options.solid {
        match engine {
            Engine::SevenZip if format == "7z" => {
                command.arg(if solid { "-ms=on" } else { "-ms=off" });
            }
            Engine::Rar => {
                command.arg(if solid { "-s" } else { "-s-" });
            }
            _ => {}
        }
    }
    command.args(&options.arguments);
}

pub fn stream(tool: &Tool, decompress: bool, options: &Options) -> Command {
    let mut command = Command::new(&tool.path);
    if decompress {
        command.arg("-d");
        if tool.engine == Engine::Zstd {
            command.args(options.arguments.iter().filter(|a| a.starts_with("--long=")));
        }
    } else {
        configure(&mut command, tool.engine, "", options);
        if matches!(tool.engine, Engine::Zstd | Engine::Lz4) {
            command.arg("-z");
        }
    }
    // Files are connected by inherited handles; no CLI may rename or delete a source.
    command.arg("-c");
    command
}
