use std::collections::HashSet;
use std::env;
use std::path::{Path, PathBuf};

use super::{Engine, Tool};

const CANDIDATES: &[(&str, Engine, &str)] = &[
    ("7zz", Engine::SevenZip, "7-Zip"),
    ("7z", Engine::SevenZip, "7-Zip"),
    ("7za", Engine::SevenZip, "7-Zip"),
    ("bsdtar", Engine::BsdTar, "BSD tar"),
    ("tar", Engine::Tar, "tar"),
    ("zip", Engine::Zip, "ZIP"),
    ("unzip", Engine::Unzip, "UnZip"),
    ("rar", Engine::Rar, "RAR"),
    ("unrar", Engine::Unrar, "UnRAR"),
    ("unar", Engine::Unar, "The Unarchiver"),
    ("zstd", Engine::Zstd, "zstd"),
    ("gzip", Engine::Gzip, "gzip"),
    ("pigz", Engine::Pigz, "pigz"),
    ("bzip2", Engine::Bzip2, "bzip2"),
    ("pbzip2", Engine::Pbzip2, "pbzip2"),
    ("xz", Engine::Xz, "xz"),
    ("lz4", Engine::Lz4, "LZ4"),
];

pub fn executable(path: &Path) -> bool {
    let Ok(meta) = path.metadata() else { return false };
    if !meta.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        meta.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        path.extension().is_some_and(|e| e.eq_ignore_ascii_case("exe"))
    }
}

fn paths() -> Vec<PathBuf> {
    let mut paths: Vec<_> = env::var_os("PATH").map(|p| env::split_paths(&p).collect()).unwrap_or_default();
    // GUI launches often have only the system PATH, without package managers.
    #[cfg(unix)]
    paths.extend(
        ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"].map(PathBuf::from),
    );
    #[cfg(windows)]
    {
        for key in ["ProgramFiles", "ProgramFiles(x86)"] {
            if let Some(root) = env::var_os(key) {
                paths.extend(["7-Zip", "WinRAR"].map(|dir| PathBuf::from(&root).join(dir)));
            }
        }
        if let Some(root) = env::var_os("SystemRoot") {
            paths.push(PathBuf::from(root).join("System32"));
        }
    }
    paths.retain(|p| p.is_absolute());
    paths
}

pub fn discover(manual: Vec<Tool>) -> Vec<Tool> {
    discover_in(&paths(), manual)
}

fn discover_in(paths: &[PathBuf], manual: Vec<Tool>) -> Vec<Tool> {
    let mut tools = Vec::new();
    let mut seen = HashSet::new();
    let mut add = |tool: Tool| {
        if !tool.path.is_absolute() || !executable(&tool.path) {
            return;
        }
        let resolved = tool.path.canonicalize().unwrap_or_else(|_| tool.path.clone());
        let path_key = resolved.to_string_lossy().into_owned();
        let path_key = if cfg!(windows) { path_key.to_lowercase() } else { path_key };
        let key = (tool.engine.name(), path_key);
        if seen.insert(key) {
            tools.push(tool);
        }
    };
    // Explicit profiles keep the user's title when they match an auto-detected tool.
    for tool in manual {
        add(tool);
    }
    for &(program, engine, name) in CANDIDATES {
        for directory in paths {
            let path = directory.join(if cfg!(windows) { format!("{program}.exe") } else { program.into() });
            let engine = if engine == Engine::Tar
                && path
                    .canonicalize()
                    .ok()
                    .and_then(|p| p.file_name().map(|n| n == "bsdtar"))
                    .unwrap_or(false)
            {
                Engine::BsdTar
            } else {
                engine
            };
            add(Tool { name: name.into(), path, engine });
        }
    }
    #[cfg(target_os = "macos")]
    for root in [
        Some(PathBuf::from("/Applications")),
        env::var_os("HOME").map(|p| PathBuf::from(p).join("Applications")),
    ]
    .into_iter()
    .flatten()
    {
        for name in ["7zz", "keka7z", "7z"] {
            add(Tool {
                name: "Keka (7-Zip)".into(),
                path: root.join("Keka.app/Contents/Resources").join(name),
                engine: Engine::SevenZip,
            });
        }
    }
    tools
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovers_executables_deduplicates_aliases_and_keeps_manual_names() {
        let dir = tempfile::tempdir().unwrap();
        let binary = dir.path().join(if cfg!(windows) { "7zz.exe" } else { "7zz" });
        std::fs::write(&binary, "test").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&binary, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let tool = Tool { name: "My 7-Zip".into(), path: binary, engine: Engine::SevenZip };
        let found = discover_in(&[dir.path().into(), dir.path().into()], vec![tool.clone()]);
        assert_eq!(found, vec![tool]);
        assert!(discover_in(&[PathBuf::from("relative")], Vec::new()).is_empty());
    }
}
