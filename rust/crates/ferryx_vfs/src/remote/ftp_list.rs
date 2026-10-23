//! FTP listings read into rows: `MLSD` facts (RFC 3659) where the server
//! has them, else `LIST` lines as `ls -l` prints them (the owner and group
//! names kept), else as Windows' IIS prints them.

use chrono::{Datelike, NaiveDate, NaiveDateTime, TimeZone, Utc};
use ferryx_core::entry::EntryKind;

use super::entries::{mode_of_text, RemoteMeta};

/// One row of a listing: its name and what the server said of it.
#[derive(Clone, Debug)]
pub struct Row {
    pub name: String,
    pub meta: RemoteMeta,
}

/// An `MLSD` / `MLST` line: `type=file;size=12;modify=20240101120000; name`.
/// `.` and `..` (`cdir`, `pdir`) are no rows.
pub fn parse_mlsx(line: &str) -> Option<Row> {
    let line = line.trim_start_matches(' ');
    let space = line.find("; ").map(|at| at + 1).or_else(|| line.find(' '))?;
    let (facts, name) = (&line[..space], &line[space + 1..]);
    let name = name.trim_end_matches(['\r', '\n']);
    if name.is_empty() {
        return None;
    }
    let mut meta = RemoteMeta { kind: Some(EntryKind::File), ..Default::default() };
    for fact in facts.split(';') {
        let Some((key, value)) = fact.split_once('=') else { continue };
        match key.to_ascii_lowercase().as_str() {
            "type" => {
                let lower = value.to_ascii_lowercase();
                meta.kind = Some(match lower.as_str() {
                    "cdir" | "pdir" => return None,
                    "dir" => EntryKind::Directory,
                    "file" => EntryKind::File,
                    _ if lower.starts_with("os.unix=slink") || lower.starts_with("os.unix=symlink") => {
                        if let Some((_, target)) = value.split_once(':') {
                            meta.symlink_target = Some(target.to_string());
                        }
                        EntryKind::Symlink
                    }
                    _ => EntryKind::Other,
                });
            }
            "size" | "sizd" => meta.size = value.parse().ok(),
            "modify" => meta.modified_ms = mlsx_time(value),
            "create" => meta.created_ms = mlsx_time(value),
            "unix.mode" => meta.mode = u32::from_str_radix(value, 8).ok().map(|m| m & 0o7777),
            "unix.uid" | "unix.owner" => meta.uid = value.parse().ok(),
            "unix.gid" | "unix.group" => meta.gid = value.parse().ok(),
            "unix.ownername" => meta.owner = value.to_string(),
            "unix.groupname" => meta.group = value.to_string(),
            _ => {}
        }
    }
    Some(Row { name: name.to_string(), meta })
}

/// `YYYYMMDDHHMMSS[.sss]`, in UTC.
fn mlsx_time(value: &str) -> Option<i64> {
    let (whole, fraction) = value.split_once('.').unwrap_or((value, ""));
    let time = NaiveDateTime::parse_from_str(whole, "%Y%m%d%H%M%S").ok()?;
    let millis: i64 = format!("{fraction:0<3}").get(..3).and_then(|m| m.parse().ok()).unwrap_or(0);
    Some(Utc.from_utc_datetime(&time).timestamp_millis() + millis)
}

/// The time `MFMT` takes: `YYYYMMDDHHMMSS`, in UTC.
pub fn mfmt_time(ms: i64) -> Option<String> {
    Utc.timestamp_millis_opt(ms).single().map(|t| t.format("%Y%m%d%H%M%S").to_string())
}

const MONTHS: [&str; 12] =
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

/// A `LIST` line: `drwxr-xr-x  2 me staff  4096 Jan  1 12:00 name` (a time
/// in this year or the last), `… Jan  1  2020 name`, or IIS's
/// `01-15-20  10:30AM  <DIR>  name`. `None` for `total 12`, `.`, `..` and
/// what cannot be read.
pub fn parse_list(line: &str, now_ms: i64) -> Option<Row> {
    parse_unix(line, now_ms).or_else(|| parse_dos(line))
}

fn parse_unix(line: &str, now_ms: i64) -> Option<Row> {
    let spans = spans(line);
    if spans.len() < 8 {
        return None;
    }
    let field = |i: usize| &line[spans[i].0..spans[i].1];
    let perms = field(0);
    let mode = mode_of_text(perms.get(..10)?)?;
    // Some servers leave out the group: then the size comes fourth.
    let month_at = (3..spans.len().saturating_sub(3)).find(|&i| {
        MONTHS.contains(&field(i).to_ascii_lowercase().as_str())
            && field(i - 1).bytes().all(|b| b.is_ascii_digit())
    })?;
    let size: u64 = field(month_at - 1).parse().ok()?;
    let (owner, group) = match month_at {
        5 => (field(2), field(3)),
        4 => (field(2), ""),
        _ => ("", ""),
    };
    let month = MONTHS.iter().position(|m| *m == field(month_at).to_ascii_lowercase())? as u32 + 1;
    let day: u32 = field(month_at + 1).parse().ok()?;
    let when = field(month_at + 2);
    let name_at = spans.get(month_at + 3)?.0;
    let mut name = &line[name_at..];
    let modified_ms = unix_time(month, day, when, now_ms);
    let kind = super::entries::kind_of_mode(mode).unwrap_or(EntryKind::Other);
    let mut target = None;
    if kind == EntryKind::Symlink {
        if let Some((link, to)) = name.split_once(" -> ") {
            name = link;
            target = Some(to.to_string());
        }
    }
    if name == "." || name == ".." || name.is_empty() {
        return None;
    }
    Some(Row {
        name: name.to_string(),
        meta: RemoteMeta {
            kind: Some(kind),
            symlink_target: target,
            size: Some(size),
            modified_ms,
            mode: Some(mode),
            owner: owner.to_string(),
            group: group.to_string(),
            ..Default::default()
        },
    })
}

/// `12:00` this year (or last, when that would be in the future), or a
/// year at midnight; the server's clock is taken as UTC.
fn unix_time(month: u32, day: u32, when: &str, now_ms: i64) -> Option<i64> {
    let now = Utc.timestamp_millis_opt(now_ms).single()?;
    if let Some((hour, minute)) = when.split_once(':') {
        let (hour, minute): (u32, u32) = (hour.parse().ok()?, minute.parse().ok()?);
        let mut year = now.year();
        let at = |year: i32| NaiveDate::from_ymd_opt(year, month, day)?.and_hms_opt(hour, minute, 0);
        let mut time = at(year)?;
        if Utc.from_utc_datetime(&time).timestamp_millis() > now_ms + 86_400_000 {
            year -= 1;
            time = at(year)?;
        }
        Some(Utc.from_utc_datetime(&time).timestamp_millis())
    } else {
        let year: i32 = when.parse().ok()?;
        let time = NaiveDate::from_ymd_opt(year, month, day)?.and_hms_opt(0, 0, 0)?;
        Some(Utc.from_utc_datetime(&time).timestamp_millis())
    }
}

fn parse_dos(line: &str) -> Option<Row> {
    let file = suppaftp::list::File::from_dos_line(line).ok()?;
    let name = file.name().to_string();
    if name == "." || name == ".." {
        return None;
    }
    let modified_ms = file
        .modified()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_millis()).ok());
    Some(Row {
        name,
        meta: RemoteMeta {
            kind: Some(if file.is_directory() { EntryKind::Directory } else { EntryKind::File }),
            size: if file.is_directory() { None } else { Some(file.size() as u64) },
            modified_ms,
            ..Default::default()
        },
    })
}

/// Where each run of non-blank characters starts and ends.
fn spans(line: &str) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut start = None;
    for (i, c) in line.char_indices() {
        if c == ' ' || c == '\t' {
            if let Some(s) = start.take() {
                out.push((s, i));
            }
        } else if start.is_none() {
            start = Some(i);
        }
    }
    if let Some(s) = start {
        out.push((s, line.len()));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(text: &str) -> i64 {
        Utc.from_utc_datetime(&NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap())
            .timestamp_millis()
    }

    #[test]
    fn reads_mlsd_facts() {
        let row = parse_mlsx(
            "type=file;size=1234;modify=20240102030405.5;UNIX.mode=0644;UNIX.ownername=me; a b.txt",
        )
        .unwrap();
        assert_eq!(row.name, "a b.txt");
        assert_eq!(row.meta.kind, Some(EntryKind::File));
        assert_eq!(row.meta.size, Some(1234));
        assert_eq!(row.meta.modified_ms, Some(ms("2024-01-02 03:04") + 5_500));
        assert_eq!(row.meta.mode, Some(0o644));
        assert_eq!(row.meta.owner, "me");
        assert_eq!(parse_mlsx("type=dir;modify=20240102030405; Ünïcödé").unwrap().name, "Ünïcödé");
        assert!(parse_mlsx("type=cdir; .").is_none());
        assert!(parse_mlsx("type=pdir;modify=20240102030405; ..").is_none());
        let link = parse_mlsx("type=OS.unix=slink:/srv/www;modify=20240102030405; www").unwrap();
        assert_eq!(link.meta.kind, Some(EntryKind::Symlink));
        assert_eq!(link.meta.symlink_target.as_deref(), Some("/srv/www"));
        assert_eq!(mfmt_time(ms("2024-01-02 03:04")).as_deref(), Some("20240102030400"));
    }

    #[test]
    fn reads_ls_lines() {
        let now = ms("2024-03-10 12:00");
        let row =
            parse_list("-rw-r--r--    1 me       staff        12 Jan  5 10:30 notes with spaces.txt", now)
                .unwrap();
        assert_eq!(row.name, "notes with spaces.txt");
        assert_eq!(row.meta.size, Some(12));
        assert_eq!(row.meta.owner, "me");
        assert_eq!(row.meta.group, "staff");
        assert_eq!(row.meta.mode, Some(0o100644));
        assert_eq!(row.meta.modified_ms, Some(ms("2024-01-05 10:30")));
        // A time later in the year than now is last year's.
        let old = parse_list("drwxr-xr-x 2 me staff 4096 Dec 24 18:00 xmas", now).unwrap();
        assert_eq!(old.meta.modified_ms, Some(ms("2023-12-24 18:00")));
        assert_eq!(old.meta.kind, Some(EntryKind::Directory));
        let year = parse_list("-rw-r--r-- 1 me staff 5 Jun  1  2019 old.log", now).unwrap();
        assert_eq!(year.meta.modified_ms, Some(ms("2019-06-01 00:00")));
        let link = parse_list("lrwxrwxrwx 1 me staff 9 Jan 1 2020 www -> /srv/www", now).unwrap();
        assert_eq!((link.name.as_str(), link.meta.symlink_target.as_deref()), ("www", Some("/srv/www")));
        let no_group = parse_list("-rw-r--r-- 1 ftp 77 Feb 2 2021 a", now).unwrap();
        assert_eq!(
            (no_group.meta.size, no_group.meta.owner.as_str(), no_group.meta.group.as_str()),
            (Some(77), "ftp", "")
        );
        assert!(parse_list("total 24", now).is_none());
        assert!(parse_list("drwxr-xr-x 2 me staff 4096 Jan 1 2020 .", now).is_none());
        let dos = parse_list("01-15-20  10:30AM       <DIR>          Folder", now).unwrap();
        assert_eq!((dos.name.as_str(), dos.meta.kind), ("Folder", Some(EntryKind::Directory)));
    }
}
