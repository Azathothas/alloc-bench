//! What the measurement ran on.
//!
//!  A number without its conditions is worse than no number. This module
//! collects them once per run so the report can print them beside every table
//! and a reader can tell whether two runs are comparable at all.

use crate::exec;
use crate::model::{HostEnv, HostInfo};
use std::collections::BTreeMap;

/// ISO-8601 UTC, computed from the clock without pulling in a date library.
pub fn now_iso8601() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let days = secs / 86_400;
    let rem = secs % 86_400;
    let (h, mi, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);

    // Civil-from-days (Howard Hinnant's algorithm), so this is correct across
    // leap years rather than approximately right.
    let z = days as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };

    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, h, mi, s)
}

/// The first `key: value` line of some `/proc`-shaped text.
fn first_field_in(s: &str, key: &str) -> Option<String> {
    for line in s.lines() {
        if let Some((k, v)) = line.split_once(':') {
            if k.trim() == key {
                return Some(v.trim().to_string());
            }
        }
    }
    None
}

fn first_field(path: &str, key: &str) -> Option<String> {
    first_field_in(&std::fs::read_to_string(path).ok()?, key)
}

/// The cpuset an operator asked every container to be pinned to, if any.
///
///  Read from `ALLOC_BENCH_CPUSET`, and empty is the same as unset: a variable
/// exported as `""` by a shell that meant to clear it must not become
/// `--cpuset-cpus=`, which docker rejects, and must not be recorded as a
/// constraint that was not applied.
pub fn cpuset() -> Option<String> {
    match std::env::var("ALLOC_BENCH_CPUSET") {
        Ok(v) if !v.trim().is_empty() => Some(v.trim().to_string()),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
//  The machine properties T-025 named as missing.
//
//  EVERY PROBE BELOW RETURNS A `Result`, NEVER A BARE `Option`. The rule this
// obeys is the one `T-024` cost a run to learn: a check that answers "no" when
// it could not look has failed open. `None` for "this host has no cpufreq" and
// `None` for "the read blew up" are the same value, so the reason travels
// beside it and `probe()` files it under `unread`.

/// The contents of a `/sys` or `/proc` file, trimmed.
///
///  The error string names the path AND the reason, because "no such file" and
/// "permission denied" mean opposite things here: the first is a property of the
/// kernel build, the second a property of the sandbox.
fn read_sys(path: &str) -> Result<String, String> {
    match std::fs::read_to_string(path) {
        Ok(s) if s.trim().is_empty() => Err(format!("{}: present but empty", path)),
        Ok(s) => Ok(s.trim().to_string()),
        Err(e) => Err(format!("{}: {}", path, e.kind())),
    }
}

/// The selected mode out of a `/sys` multi-choice file.
///
/// `always [madvise] never` → `madvise`.  A file with no bracket is NOT
/// reported as "never": it is an unrecognised format and says so.
fn parse_bracketed(s: &str) -> Result<String, String> {
    let open = s
        .find('[')
        .ok_or_else(|| format!("no [selection] in {:?}", s))?;
    let close = s[open..]
        .find(']')
        .ok_or_else(|| format!("unterminated [ in {:?}", s))?;
    let inner = &s[open + 1..open + close];
    if inner.is_empty() {
        return Err(format!("empty [] in {:?}", s));
    }
    Ok(inner.to_string())
}

/// How many hardware threads a CPU list names. `0,4` → 2; `0-1` → 2; `3` → 1.
///
///  Used for `thread_siblings_list`, whose two spellings are both real: the
/// comma form on machines whose SMT siblings are numbered apart, the range form
/// on machines where they are adjacent.
fn parse_cpu_list_len(s: &str) -> Result<usize, String> {
    let mut n = 0usize;
    for part in s.split(',').filter(|p| !p.trim().is_empty()) {
        let part = part.trim();
        match part.split_once('-') {
            Some((lo, hi)) => {
                let lo: usize = lo
                    .parse()
                    .map_err(|_| format!("not a cpu range: {:?}", part))?;
                let hi: usize = hi
                    .parse()
                    .map_err(|_| format!("not a cpu range: {:?}", part))?;
                if hi < lo {
                    return Err(format!("descending cpu range: {:?}", part));
                }
                n += hi - lo + 1;
            }
            None => {
                part.parse::<usize>()
                    .map_err(|_| format!("not a cpu id: {:?}", part))?;
                n += 1;
            }
        }
    }
    if n == 0 {
        return Err(format!("no cpus in {:?}", s));
    }
    Ok(n)
}

/// CPU 0's caches, as `L1d=32K L1i=32K L2=1024K L3=33792K`.
///
///  `index*` is walked by number rather than globbed so the order is the
/// kernel's own - level-ascending - and two hosts' strings are comparable.
fn probe_caches() -> Result<String, String> {
    let base = "/sys/devices/system/cpu/cpu0/cache";
    let mut out: Vec<String> = Vec::new();
    let mut last_err = format!("{}/index0: not present", base);
    for i in 0..10 {
        let dir = format!("{}/index{}", base, i);
        if !std::path::Path::new(&dir).exists() {
            continue;
        }
        let level = match read_sys(&format!("{}/level", dir)) {
            Ok(v) => v,
            Err(e) => {
                last_err = e;
                continue;
            }
        };
        let kind = read_sys(&format!("{}/type", dir)).unwrap_or_else(|_| "Unified".into());
        let size = match read_sys(&format!("{}/size", dir)) {
            Ok(v) => v,
            Err(e) => {
                last_err = e;
                continue;
            }
        };
        // `Data` → `d`, `Instruction` → `i`, `Unified` → nothing, which is how
        // lscpu spells it and how every CPU datasheet does.
        let suffix = match kind.as_str() {
            "Data" => "d",
            "Instruction" => "i",
            _ => "",
        };
        out.push(format!("L{}{}={}", level, suffix, size));
    }
    if out.is_empty() {
        return Err(last_err);
    }
    Ok(out.join(" "))
}

/// How many NUMA nodes the kernel exposes.
fn probe_numa() -> Result<usize, String> {
    let base = "/sys/devices/system/node";
    let rd = std::fs::read_dir(base).map_err(|e| format!("{}: {}", base, e.kind()))?;
    let n = rd
        .filter_map(|e| e.ok())
        .filter(|e| {
            //  `node` with nothing after it is NOT a node: `all()` over an
            // empty suffix is true, so the digit test has to be told that the
            // suffix must exist at all.
            e.file_name().to_str().is_some_and(|f| {
                f.strip_prefix("node")
                    .is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
            })
        })
        .count();
    if n == 0 {
        return Err(format!("{}: no node* entries", base));
    }
    Ok(n)
}

/// One field out of `/proc/self/status`.
fn proc_self_status(key: &str) -> Result<String, String> {
    let s = std::fs::read_to_string("/proc/self/status")
        .map_err(|e| format!("/proc/self/status: {}", e.kind()))?;
    first_field_in(&s, key).ok_or_else(|| format!("/proc/self/status: no {} field", key))
}

///  The machine properties beyond CPU model and core count.
///
///  Never returns an error. A property this host does not expose is `None`
/// **with its reason in `unread`**, because a probe that reports nothing and a
/// host that has nothing must not produce the same record.
pub fn host_env() -> HostEnv {
    let mut env = HostEnv::default();
    let mut note = |k: &str, e: String| {
        env.unread.insert(k.to_string(), e);
    };

    match exec::run("getconf", &["PAGESIZE".into()], None) {
        Ok(o) if o.ok() => match o.stdout.trim().parse::<u64>() {
            Ok(v) => env.page_size_bytes = Some(v),
            Err(_) => note(
                "page_size_bytes",
                format!("getconf PAGESIZE: {:?}", o.stdout),
            ),
        },
        Ok(o) => note(
            "page_size_bytes",
            format!("getconf PAGESIZE: exit {}", o.code),
        ),
        Err(e) => note("page_size_bytes", format!("getconf: {}", e)),
    }

    match read_sys("/sys/kernel/mm/transparent_hugepage/enabled").and_then(|s| parse_bracketed(&s))
    {
        Ok(v) => env.transparent_hugepage = Some(v),
        Err(e) => note("transparent_hugepage", e),
    }
    match probe_caches() {
        Ok(v) => env.cpu_caches = Some(v),
        Err(e) => note("cpu_caches", e),
    }
    match probe_numa() {
        Ok(v) => env.numa_nodes = Some(v),
        Err(e) => note("numa_nodes", e),
    }
    match read_sys("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list")
        .and_then(|s| parse_cpu_list_len(&s))
    {
        Ok(v) => env.threads_per_core = Some(v),
        Err(e) => note("threads_per_core", e),
    }
    match read_sys("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") {
        Ok(v) => env.scaling_governor = Some(v),
        Err(e) => note("scaling_governor", e),
    }
    match proc_self_status("Cpus_allowed_list") {
        Ok(v) => env.cpus_allowed = Some(v),
        Err(e) => note("cpus_allowed", e),
    }

    env
}

pub fn host(runtime: &exec::Runtime, target_arch: Option<&str>) -> HostInfo {
    let kernel = exec::run("uname", &["-sr".into()], None)
        .map(|o| o.stdout.trim().to_string())
        .unwrap_or_default();
    let arch = exec::run("uname", &["-m".into()], None)
        .map(|o| o.stdout.trim().to_string())
        .unwrap_or_default();

    // /proc/cpuinfo names the field differently per architecture: x86 has
    // "model name", aarch64 usually has none at all and only "CPU part".
    let cpu_model = first_field("/proc/cpuinfo", "model name")
        .or_else(|| first_field("/proc/cpuinfo", "Model"))
        .or_else(|| {
            first_field("/proc/cpuinfo", "CPU part").map(|p| format!("aarch64 CPU part {}", p))
        })
        .unwrap_or_else(|| "unknown".into());

    let cpu_count = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(0);
    let mem_total_kb = first_field("/proc/meminfo", "MemTotal")
        .and_then(|v| v.split_whitespace().next().and_then(|n| n.parse().ok()))
        .unwrap_or(0);

    //  Emulation. A run whose target architecture is not the host's went
    // through binfmt/QEMU. Those timings are recorded and then excluded from
    // ranking: user-mode emulation changes the instruction mix and the memory
    // behaviour, so an allocator comparison under it measures the emulator as
    // much as the allocator.
    let emulated = match target_arch {
        Some(t) => !arch.is_empty() && t != arch,
        None => false,
    };

    HostInfo {
        kernel,
        arch,
        cpu_model,
        cpu_count,
        mem_total_kb,
        container_runtime: runtime.bin.clone(),
        runtime_version: runtime.version.clone(),
        emulated,
        cpuset: cpuset(),
        env: host_env(),
    }
}

pub fn tool_versions() -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    for (name, args) in [
        ("git", vec!["--version"]),
        ("curl", vec!["--version"]),
        ("docker", vec!["--version"]),
        ("podman", vec!["--version"]),
    ] {
        if let Ok(o) = exec::run(
            name,
            &args.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
            None,
        ) {
            if o.ok() {
                m.insert(
                    name.to_string(),
                    o.stdout.lines().next().unwrap_or("").to_string(),
                );
            }
        }
    }
    m
}

/// CI identity, so a published result can be traced to the run that made it.
pub fn ci_info() -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    for k in [
        "GITHUB_RUN_ID",
        "GITHUB_RUN_NUMBER",
        "GITHUB_RUN_ATTEMPT",
        "GITHUB_WORKFLOW",
        "GITHUB_SHA",
        "GITHUB_REF",
        "GITHUB_REPOSITORY",
        "RUNNER_NAME",
        "RUNNER_OS",
        "RUNNER_ARCH",
        "ImageOS",
        "ImageVersion",
    ] {
        if let Ok(v) = std::env::var(k) {
            if !v.is_empty() {
                m.insert(k.to_string(), v);
            }
        }
    }
    m
}

pub fn git_commit() -> String {
    exec::run("git", &["rev-parse".into(), "HEAD".into()], None)
        .ok()
        .filter(|o| o.ok())
        .map(|o| o.stdout.trim().to_string())
        .unwrap_or_else(|| "unknown".into())
}

/// Whether TRACKED files were modified when the run started.
///
///  `git_commit` is `rev-parse HEAD` and HEAD is blind to the working tree,
/// so without this a dataset built from a modified checkout names a commit
/// that did not produce it - and nothing in the record contradicts that.
///
///  **`--untracked-files=no` is deliberate and was added after the first
/// version got it wrong.** A plain `--porcelain` counts untracked files too,
/// and `bench.yml` writes `conditions.txt` into the repository root before it
/// measures anything - so every CI dataset came out `git_dirty: true` over a
/// file no build step reads. An integrity signal that cries wolf on every CI
/// run is worse than none, because it gets ignored. Untracked files are still
/// recorded, as a count, by `git_untracked` below.
///
///  Ignored paths are excluded either way, which is what makes this usable
/// during a run: `results/local/<run-id>` is gitignored, so the run writing
/// its own output does not report itself as dirty.
///
/// `None` when git could not answer - an unknown tree state is recorded as
/// unknown rather than assumed clean.
pub fn git_dirty() -> Option<bool> {
    exec::run(
        "git",
        &[
            "status".into(),
            "--porcelain".into(),
            "--untracked-files=no".into(),
        ],
        None,
    )
    .ok()
    .filter(|o| o.ok())
    .map(|o| !o.stdout.trim().is_empty())
}

/// How many untracked, non-ignored files were present when the run started.
///
///  Recorded rather than policed. An untracked file usually cannot change a
/// binary - `conditions.txt` on a CI runner is the ordinary case - but it is
/// not *nothing*: a stray header on an include path can. A count keeps the
/// fact visible without making `git_dirty` unusable.
pub fn git_untracked() -> Option<usize> {
    exec::run(
        "git",
        &[
            "status".into(),
            "--porcelain".into(),
            "--untracked-files=all".into(),
        ],
        None,
    )
    .ok()
    .filter(|o| o.ok())
    .map(|o| o.stdout.lines().filter(|l| l.starts_with("??")).count())
}

// ---------------------------------------------------------------------------
//  The parsers above are pure functions over text so they can be tested
// WITHOUT the host they describe.  That is the point: the interesting cases -
// a `/sys` file with no bracket, SMT siblings spelled as a range, a descending
// range - cannot be produced on demand by the machine running the tests, and a
// probe only exercised against its own host is a probe tested on one input.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bracketed_selection_is_the_selected_word() {
        assert_eq!(
            parse_bracketed("always [madvise] never").unwrap(),
            "madvise"
        );
        assert_eq!(parse_bracketed("[always] madvise never").unwrap(), "always");
        assert_eq!(parse_bracketed("always madvise [never]").unwrap(), "never");
    }

    #[test]
    fn a_file_with_no_bracket_is_an_error_and_not_never() {
        //  The failure this guards: reporting "never" - a real, meaningful
        // value - for a file whose format was not understood.
        assert!(parse_bracketed("always madvise never").is_err());
        assert!(parse_bracketed("").is_err());
        assert!(parse_bracketed("always [ madvise never").is_err());
        assert!(parse_bracketed("[]").is_err());
    }

    #[test]
    fn cpu_lists_count_both_spellings() {
        assert_eq!(parse_cpu_list_len("0").unwrap(), 1); // no SMT
        assert_eq!(parse_cpu_list_len("0,4").unwrap(), 2); // siblings apart
        assert_eq!(parse_cpu_list_len("0-1").unwrap(), 2); // siblings adjacent
        assert_eq!(parse_cpu_list_len("0-3").unwrap(), 4);
        assert_eq!(parse_cpu_list_len("0-1,8-9").unwrap(), 4);
        assert_eq!(parse_cpu_list_len(" 0-3 \n").unwrap(), 4);
    }

    #[test]
    fn a_cpu_list_that_makes_no_sense_is_an_error() {
        assert!(parse_cpu_list_len("").is_err());
        assert!(parse_cpu_list_len("nonsense").is_err());
        assert!(parse_cpu_list_len("3-1").is_err());
        assert!(parse_cpu_list_len("0-x").is_err());
    }

    #[test]
    fn proc_fields_are_read_by_name() {
        let s = "Name:\tsh\nCpus_allowed:\tf\nCpus_allowed_list:\t0-3\n";
        assert_eq!(first_field_in(s, "Cpus_allowed_list").unwrap(), "0-3");
        assert_eq!(first_field_in(s, "Name").unwrap(), "sh");
        assert!(first_field_in(s, "Cpus").is_none());
    }

    //  THE INVARIANT THE WHOLE STRUCT EXISTS FOR. A field that is `None` and
    // carries no note is a probe that answered "no" without looking, which is
    // the T-024 defect one layer up.
    #[test]
    fn every_absent_property_names_the_reason_it_is_absent() {
        let e = host_env();
        //  Printed, not just asserted. `RULES.md` §4: never record a
        // capability as absent without the probe's output. `cargo test` hides
        // this unless the test fails or `--nocapture` is passed, which is
        // exactly when a reader needs to see what this host actually answered.
        eprintln!("host_env() on this machine: {:#?}", e);
        let missing: Vec<&str> = [
            ("page_size_bytes", e.page_size_bytes.is_none()),
            ("transparent_hugepage", e.transparent_hugepage.is_none()),
            ("cpu_caches", e.cpu_caches.is_none()),
            ("numa_nodes", e.numa_nodes.is_none()),
            ("threads_per_core", e.threads_per_core.is_none()),
            ("scaling_governor", e.scaling_governor.is_none()),
            ("cpus_allowed", e.cpus_allowed.is_none()),
        ]
        .into_iter()
        .filter(|(_, absent)| *absent)
        .map(|(k, _)| k)
        .filter(|k| !e.unread.contains_key(*k))
        .collect();
        assert!(
            missing.is_empty(),
            "these came back empty with no reason recorded: {:?}",
            missing
        );
    }

    //  And the converse, so the map cannot quietly grow keys nothing reads.
    #[test]
    fn a_reason_is_only_recorded_for_a_property_that_is_absent() {
        let e = host_env();
        let known = [
            "page_size_bytes",
            "transparent_hugepage",
            "cpu_caches",
            "numa_nodes",
            "threads_per_core",
            "scaling_governor",
            "cpus_allowed",
        ];
        for k in e.unread.keys() {
            assert!(
                known.contains(&k.as_str()),
                "unread names an unknown key {:?}",
                k
            );
        }
    }
}
