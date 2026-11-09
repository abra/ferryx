use super::Engine;

/// User defaults are checked independently of the UI, before any process starts.
#[derive(Clone, Debug, Default)]
pub struct Options {
    pub level: Option<u32>,
    pub threads: Option<u32>,
    pub solid: Option<bool>,
    pub arguments: Vec<String>,
}

impl Options {
    pub fn validate(&self, engine: Option<Engine>) -> Result<(), String> {
        let levels = match engine {
            None | Some(Engine::SevenZip | Engine::Zip | Engine::Pigz | Engine::Xz) => Some(0..=9),
            Some(Engine::BsdTar | Engine::Gzip | Engine::Bzip2 | Engine::Pbzip2) => Some(1..=9),
            Some(Engine::Zstd) => Some(1..=22),
            Some(Engine::Lz4) => Some(1..=12),
            Some(Engine::Rar) => Some(0..=5),
            _ => None,
        };
        if self.level.is_some_and(|value| !levels.is_some_and(|range| range.contains(&value))) {
            return Err("Unsupported compression level".into());
        }
        if self.threads.is_some_and(|value| {
            !(1..=256).contains(&value)
                || !matches!(
                    engine,
                    Some(
                        Engine::SevenZip
                            | Engine::BsdTar
                            | Engine::Pigz
                            | Engine::Pbzip2
                            | Engine::Xz
                            | Engine::Zstd
                            | Engine::Rar
                    )
                )
        }) {
            return Err("Unsupported thread count".into());
        }
        if self.solid.is_some() && !matches!(engine, Some(Engine::SevenZip | Engine::Rar)) {
            return Err("Solid mode is unavailable for this engine".into());
        }
        if self.arguments.len() > 64 || self.arguments.iter().map(String::len).sum::<usize>() > 8192 {
            return Err("Too many custom arguments".into());
        }
        for argument in &self.arguments {
            if !allowed(engine, argument) {
                // Do not echo arbitrary text: it might contain an entered secret.
                return Err("Unsupported custom argument; use compression or format options only".into());
            }
        }
        Ok(())
    }
}

fn allowed(engine: Option<Engine>, argument: &str) -> bool {
    use std::sync::LazyLock;
    static PATTERNS: LazyLock<Vec<(Engine, regex::Regex)>> = LazyLock::new(|| {
        [
            (Engine::SevenZip, r"-m[a-zA-Z0-9:]*=[a-zA-Z0-9_:+,./%=-]+"),
            (Engine::Zip, r"-[0-9]|-Z(?:store|deflate|bzip2)|-(?:y|X)"),
            (Engine::Tar, r"--format=(?:gnu|pax|posix|ustar)|--numeric-owner"),
            (Engine::BsdTar, r"--format=(?:gnutar|pax|ustar)|--options=(?:(?:gzip|bzip2|xz|zstd|lz4):)?(?:compression-level|threads)=[0-9]+"),
            (Engine::Gzip, r"-[1-9]|-n|--no-name|--rsyncable"),
            (Engine::Pigz, r"-(?:[0-9]|11|n|i|R)|-(?:p|b)[0-9]+|--(?:processes|blocksize)=[0-9]+|--(?:rsyncable|independent|no-name)"),
            (Engine::Bzip2, r"-[1-9]|-s|--small"),
            (Engine::Pbzip2, r"-[1-9]|-p[0-9]+|-b[0-9]+|-m[0-9]+"),
            (Engine::Xz, r"-[0-9]|-e|--extreme|-T[0-9]+|--threads=[0-9]+|--check=(?:crc32|crc64|sha256|none)|--(?:lzma2|block-size|memlimit-compress)=[a-zA-Z0-9_:=,.-]+"),
            (Engine::Zstd, r"-[1-9][0-9]?|-T[0-9]+|--threads=[0-9]+|--(?:long|fast)=[0-9]+|--(?:ultra|rsyncable|single-thread|no-check|check)|--zstd=[a-zA-Z0-9_=,.-]+"),
            (Engine::Lz4, r"-(?:[1-9]|1[0-2])|-B(?:[4-7]|I|D|X)|--fast=[0-9]+|--(?:favor-decSpeed|no-frame-crc|frame-crc|content-size|no-content-size)"),
            (Engine::Rar, r"-m[0-5]|-mt[0-9]+|-md[0-9]+[kKmMgG]?|-s-?|-ma[45]"),
            (Engine::Unrar, r"-ai|-c-|-sc[a-zA-Z]+"),
            (Engine::Unzip, r"-(?:C|L|U|a|aa|j|X)"),
            (Engine::Unar, r"--no-recursion|--no-directory|--copy-time"),
        ].into_iter().map(|(engine, pattern)| (engine, regex::Regex::new(&format!("^(?:{pattern})$")).expect("fixed option pattern"))).collect()
    });
    !argument.contains(['\0', '\r', '\n'])
        && PATTERNS.iter().any(|(e, pattern)| Some(*e) == engine && pattern.is_match(argument))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn custom_options_cannot_change_inputs_outputs_or_execute_commands() {
        for engine in [Engine::Tar, Engine::BsdTar, Engine::SevenZip, Engine::Zstd, Engine::Gzip] {
            for argument in [
                "--",
                "--rm",
                "-o/tmp/out",
                "--output=/tmp/out",
                "-psecret",
                "@list",
                "--checkpoint-action=exec=sh",
                "file.txt",
                "-si",
                "-so",
            ] {
                assert!(
                    Options { arguments: vec![argument.into()], ..Default::default() }
                        .validate(Some(engine))
                        .is_err(),
                    "{engine:?} accepted {argument}"
                );
            }
        }
        assert!(Options {
            arguments: vec!["--long=27".into()],
            level: Some(19),
            threads: Some(2),
            ..Default::default()
        }
        .validate(Some(Engine::Zstd))
        .is_ok());
        assert!(Options { arguments: vec!["-m0=lzma2".into()], ..Default::default() }
            .validate(Some(Engine::SevenZip))
            .is_ok());
    }
}
