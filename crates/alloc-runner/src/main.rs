//! alloc-runner -- the instrument.
//!
//! This binary runs INSIDE the benchmark container. It generates the corpus,
//! reads the ELF to establish which allocator is really present, runs the
//! correctness gate, and takes the measurements. The host orchestrator
//! (`alloc-bench`) never times anything itself: putting `docker run` inside the
//! timed region would measure the container runtime.
//!
//!  EXIT CODES, uniform across every subcommand:
//!   0  the measurement ran and the thing passed
//!   1  the measurement ran and the thing FAILED
//!   2  the measurement could not run (missing input, bad arguments)
//!
//!  2 is never reported as a pass. A configuration that could not be measured
//! and a configuration that was measured and lost are different results, and
//! the report prints them differently.

mod ar;
mod aslr;
mod corpus;
mod elf;
mod ident;
mod json;
mod measure;
mod patchrg;
mod preload;
mod verify;

use elf::LinkKind;
use json::J;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const EXIT_OK: u8 = 0;
const EXIT_FAILED: u8 = 1;
const EXIT_CANNOT_RUN: u8 = 2;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        usage();
        return ExitCode::from(EXIT_CANNOT_RUN);
    }
    let flags = parse_flags(&args[2..]);

    //  Same defect as alloc-bench, and it bites harder here: help was matched
    // only at args[1], so `alloc-runner patch-rg --help` would PATCH A SOURCE
    // TREE and `gen-corpus --help` would write a corpus. A request to read the
    // usage must never be a request to act. Answered before dispatch; `-h` is
    // scanned in the raw argv because `parse_flags` only recognises `--`.
    if flags.contains_key("help") || args[2..].iter().any(|a| a == "-h") {
        usage();
        return ExitCode::from(EXIT_OK);
    }

    let code = match args[1].as_str() {
        "gen-corpus" => cmd_gen_corpus(&flags),
        "identify" => cmd_identify(&flags),
        "verify" => cmd_verify(&flags),
        "measure" => cmd_measure(&flags),
        "archive-check" => cmd_archive_check(&flags),
        "ar-members" => cmd_ar_members(&flags),
        "ar-unresolved" => cmd_ar_unresolved(&flags),
        "patch-rg" => cmd_patch_rg(&flags),
        "aslr-probe" => cmd_aslr_probe(&flags),
        "preload-check" => cmd_preload_check(&flags),
        "workloads" => cmd_workloads(),
        "selftest" => cmd_selftest(),
        "-h" | "--help" | "help" => {
            usage();
            EXIT_OK
        }
        other => {
            eprintln!("alloc-runner: unknown subcommand: {}", other);
            usage();
            EXIT_CANNOT_RUN
        }
    };
    ExitCode::from(code)
}

fn usage() {
    eprintln!(
        r#"alloc-runner -- the in-container instrument for alloc-bench

  gen-corpus    --out DIR --seed N --profile smoke|standard|large
  identify      --bin PATH --expect-allocator ID [--expect-kind static|static-pie|dynamic]
                [--replacement]
  verify        --bin PATH --corpus DIR
  measure       --bin PATH --corpus DIR --workload NAME --repeat N [--warmup N]
                [--timeout S] [--env K=V ...]
  archive-check --archive PATH --symbol NAME [--expect-providers N]
  ar-unresolved --archive PATH (--symbols A,B,C | --baseline PATH)
  patch-rg      --src DIR [--shim-path PATH --shim-feature NAME]
  aslr-probe    --bin PATH --corpus DIR [--runs N] [--expect randomised|fixed]
  preload-check --bin PATH --so PATH --corpus DIR --expect-allocator ID [--runs N]
  workloads     list the workload definitions
  selftest      offline checks of the instrument itself

Exit: 0 ran and passed, 1 ran and failed, 2 could not run."#
    );
}

// ---------------------------------------------------------------------------
// Argument handling. Deliberately tiny: a CLI parser is a dependency the
// container image would have to build, and this surface is fixed.

type Flags = BTreeMap<String, Vec<String>>;

fn parse_flags(args: &[String]) -> Flags {
    let mut out: Flags = BTreeMap::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if let Some(name) = a.strip_prefix("--") {
            if i + 1 < args.len() && !args[i + 1].starts_with("--") {
                out.entry(name.to_string())
                    .or_default()
                    .push(args[i + 1].clone());
                i += 2;
            } else {
                out.entry(name.to_string()).or_default().push("true".into());
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    out
}

fn one<'a>(f: &'a Flags, k: &str) -> Option<&'a str> {
    f.get(k).and_then(|v| v.first()).map(|s| s.as_str())
}
fn has(f: &Flags, k: &str) -> bool {
    f.contains_key(k)
}
fn num(f: &Flags, k: &str, default: u64) -> u64 {
    one(f, k).and_then(|s| s.parse().ok()).unwrap_or(default)
}

fn emit(v: &J) {
    println!("{}", v.to_string());
}

// ---------------------------------------------------------------------------

fn resolve_profile(f: &Flags) -> Result<&'static corpus::Profile, u8> {
    let name = one(f, "profile").unwrap_or("standard");
    corpus::profile(name).ok_or_else(|| {
        eprintln!(
            "alloc-runner: unknown profile {:?}; known: {}",
            name,
            corpus::PROFILES
                .iter()
                .map(|p| p.name)
                .collect::<Vec<_>>()
                .join(", ")
        );
        EXIT_CANNOT_RUN
    })
}

fn cmd_gen_corpus(f: &Flags) -> u8 {
    let Some(out) = one(f, "out") else {
        eprintln!("alloc-runner gen-corpus: --out is required");
        return EXIT_CANNOT_RUN;
    };
    let prof = match resolve_profile(f) {
        Ok(p) => p,
        Err(c) => return c,
    };
    let seed = num(f, "seed", 20260901);
    let out = PathBuf::from(out);

    match corpus::generate(Some(&out), seed, prof) {
        Ok(t) => {
            // Two files, on purpose. manifest.json is provenance the
            // orchestrator records with the results; truth.kv is what `verify`
            // reads back, in a format that needs no parser in this binary.
            let manifest = t.to_json(seed, prof);
            if let Err(e) = std::fs::write(out.join("manifest.json"), manifest.to_string()) {
                eprintln!("alloc-runner: writing manifest: {}", e);
                return EXIT_CANNOT_RUN;
            }
            let kv = format!(
                "files={}\nbytes={}\nlines={}\nliteral_lines={}\nliteral_files={}\nlower_lines={}\nunicode_lines={}\nregex_lines={}\ndigest={:016x}\nseed={}\nprofile={}\n",
                t.files, t.bytes, t.lines, t.literal_lines, t.literal_files, t.lower_lines,
                t.unicode_lines, t.regex_lines, t.digest, seed, prof.name
            );
            if let Err(e) = std::fs::write(out.join("truth.kv"), kv) {
                eprintln!("alloc-runner: writing truth.kv: {}", e);
                return EXIT_CANNOT_RUN;
            }
            emit(&manifest);
            EXIT_OK
        }
        Err(e) => {
            eprintln!("alloc-runner gen-corpus: {}", e);
            EXIT_CANNOT_RUN
        }
    }
}

fn read_truth(corpus_dir: &Path) -> Result<corpus::Truth, String> {
    let p = corpus_dir.join("truth.kv");
    let s = std::fs::read_to_string(&p).map_err(|e| format!("{}: {}", p.display(), e))?;
    let mut m: BTreeMap<&str, &str> = BTreeMap::new();
    for line in s.lines() {
        if let Some((k, v)) = line.split_once('=') {
            m.insert(k.trim(), v.trim());
        }
    }
    let g = |k: &str| -> u64 { m.get(k).and_then(|v| v.parse().ok()).unwrap_or(0) };
    Ok(corpus::Truth {
        files: g("files"),
        bytes: g("bytes"),
        lines: g("lines"),
        literal_lines: g("literal_lines"),
        literal_files: g("literal_files"),
        lower_lines: g("lower_lines"),
        unicode_lines: g("unicode_lines"),
        regex_lines: g("regex_lines"),
        digest: u64::from_str_radix(m.get("digest").unwrap_or(&"0"), 16).unwrap_or(0),
    })
}

fn cmd_identify(f: &Flags) -> u8 {
    let Some(bin) = one(f, "bin") else {
        eprintln!("alloc-runner identify: --bin is required");
        return EXIT_CANNOT_RUN;
    };
    let e = match elf::parse(Path::new(bin)) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("alloc-runner identify: {}", err);
            return EXIT_CANNOT_RUN;
        }
    };
    let expect_alloc = one(f, "expect-allocator").unwrap_or("system");
    let expect_kind = one(f, "expect-kind").and_then(|k| match k {
        "static" => Some(LinkKind::Static),
        "static-pie" => Some(LinkKind::StaticPie),
        "dynamic" => Some(LinkKind::Dynamic),
        _ => None,
    });
    let verdict = ident::judge(
        &e,
        expect_alloc,
        expect_kind.as_ref(),
        has(f, "replacement"),
    );
    let size = std::fs::metadata(bin).map(|m| m.len()).unwrap_or(0);
    let mut report = ident::report_json(&e, &verdict);
    if let J::O(ref mut pairs) = report {
        pairs.push(("binary_bytes".into(), J::U(size)));
        pairs.push(("expect_allocator".into(), J::s(expect_alloc)));
    }
    emit(&report);
    if verdict.ok {
        EXIT_OK
    } else {
        for r in &verdict.reasons {
            eprintln!("alloc-runner identify: {}", r);
        }
        EXIT_FAILED
    }
}

fn cmd_verify(f: &Flags) -> u8 {
    let (Some(bin), Some(corpus_dir)) = (one(f, "bin"), one(f, "corpus")) else {
        eprintln!("alloc-runner verify: --bin and --corpus are required");
        return EXIT_CANNOT_RUN;
    };
    let truth = match read_truth(Path::new(corpus_dir)) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("alloc-runner verify: {}", e);
            return EXIT_CANNOT_RUN;
        }
    };
    if truth.files == 0 {
        eprintln!("alloc-runner verify: corpus truth says 0 files; the corpus was not generated");
        return EXIT_CANNOT_RUN;
    }
    let data = Path::new(corpus_dir).join(corpus::DATA_SUBDIR);
    if !data.is_dir() {
        eprintln!(
            "alloc-runner verify: {} has no data/ subdirectory; regenerate the corpus",
            corpus_dir
        );
        return EXIT_CANNOT_RUN;
    }
    let outcome = verify::run_gate(Path::new(bin), &data, &truth);
    emit(&J::obj(vec![
        ("ok", J::Bool(outcome.ok())),
        (
            "output_digest",
            J::s(format!("{:016x}", outcome.output_digest)),
        ),
        (
            "checks",
            J::arr(outcome.checks.iter().map(|c| c.to_json()).collect()),
        ),
    ]));
    for c in &outcome.checks {
        if !c.ok {
            eprintln!("alloc-runner verify: FAIL {}: {}", c.name, c.detail);
        }
    }
    if outcome.ok() {
        EXIT_OK
    } else {
        EXIT_FAILED
    }
}

// ---------------------------------------------------------------------------
// Workloads.
//
// Each exists for a stated reason. A workload with no reason to exist burns CI
// time and adds a column nobody can interpret.

pub struct Workload {
    pub name: &'static str,
    pub why: &'static str,
    /// `{corpus}` and `{onefile}` are substituted.
    pub args: &'static [&'static str],
    pub accept: &'static [i32],
}

pub const WORKLOADS: &[Workload] = &[
    Workload {
        name: "literal",
        why: "Literal search that prints every hit. The printer allocates per match, so this is the allocation-heaviest realistic path.",
        args: &["--no-ignore", "--hidden", "--no-messages", "ZORKMID", "{corpus}"],
        accept: &[0],
    },
    Workload {
        name: "literal-j1",
        why: "The same search pinned to one thread. Separates single-thread allocator cost from the thread-caching behaviour the parallel run exercises.",
        args: &["--no-ignore", "--hidden", "--no-messages", "-j", "1", "ZORKMID", "{corpus}"],
        accept: &[0],
    },
    Workload {
        name: "regex",
        why: "A pattern with a bounded repeat and an alternation, so the regex engine runs instead of a literal fast path.",
        args: &["--no-ignore", "--hidden", "--no-messages", r"TRACE-[0-9]{4}-(alpha|omega)", "{corpus}"],
        accept: &[0],
    },
    Workload {
        name: "nomatch",
        why: "Scans every byte and prints nothing. Isolates traversal and buffering from output allocation; exits 1 by design.",
        args: &["--no-ignore", "--hidden", "--no-messages", "QQQQ-ZZZZ-NO-SUCH-TOKEN", "{corpus}"],
        accept: &[1],
    },
    Workload {
        name: "files",
        why: "-l stops at the first hit per file, so directory walking and per-file setup dominate. This is where many small allocations live.",
        args: &["--no-ignore", "--hidden", "--no-messages", "-l", "ZORKMID", "{corpus}"],
        accept: &[0],
    },
    Workload {
        name: "json",
        why: "Structured output goes through a different buffering path from the plain printer.",
        args: &["--no-ignore", "--hidden", "--no-messages", "--json", "ZORKMID", "{corpus}"],
        accept: &[0],
    },
    Workload {
        name: "startup",
        why: "One small file. Dominated by process start and allocator initialisation, which is the cost a short-lived container command actually pays.",
        args: &["--no-ignore", "--hidden", "--no-messages", "ZORKMID", "{onefile}"],
        accept: &[0, 1],
    },
];

/// Which members of an archive define any of `--symbols`.
///
///  This is what makes libc surgery survive a libc upgrade. The prior art
/// (https://github.com/haskell-wasm/rust-alpine-mimalloc, tree/build.sh) deletes a
/// HARD-CODED list of musl object names -- `malloc.lo`, `free.lo`,
/// `lite_malloc.lo` and so on. Those names are a property of the musl release
/// that built the archive. When a future musl renames or splits one, the `ar`
/// DELETE matches nothing, both allocators end up in libc.a, and which one
/// serves `malloc` is decided by link order. Nothing fails; the numbers are
/// just wrong.
///
/// Deriving the list from the archive itself cannot go stale, and the surgery
/// script asserts on the count afterwards either way.
fn cmd_ar_members(f: &Flags) -> u8 {
    let Some(archive) = one(f, "archive") else {
        eprintln!("alloc-runner ar-members: --archive is required");
        return EXIT_CANNOT_RUN;
    };
    let symbols: Vec<&str> = one(f, "symbols")
        .unwrap_or("malloc")
        .split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .collect();
    let mut names: Vec<String> = Vec::new();
    for sym in &symbols {
        match ar::definers(Path::new(archive), sym) {
            Ok(ps) => {
                for p in ps {
                    if !names.contains(&p.member) {
                        names.push(p.member);
                    }
                }
            }
            Err(e) => {
                eprintln!("alloc-runner ar-members: {}", e);
                return EXIT_CANNOT_RUN;
            }
        }
    }
    names.sort();
    for n in &names {
        println!("{}", n);
    }
    if names.is_empty() {
        // Not an error: an archive that defines none of these symbols is a
        // fact the caller needs, and it is reported as exit 1 so a script
        // cannot mistake "nothing to delete" for "deleted successfully".
        eprintln!(
            "alloc-runner ar-members: no member of {} defines any of {:?}",
            archive, symbols
        );
        return EXIT_FAILED;
    }
    EXIT_OK
}

/// Which of these symbols does the archive REFERENCE but never DEFINE?
///
///  The question `libc-surgery` needed and could not ask. After the splice,
/// musl's own surviving objects still call `__libc_malloc`, `__libc_free` and
/// `__libc_calloc`; only mimalloc happens to define them, so every other
/// allocator's link fails on exactly those names. Now the surgery asks, and
/// supplies what is missing rather than depending on the allocator's accidents.
///
/// Prints one name per line.  Exit 0 whether or not anything is missing --
/// "nothing is missing" is the good answer here, unlike `ar-members`, where an
/// empty result means the delete would be a no-op.
fn cmd_ar_unresolved(f: &Flags) -> u8 {
    let Some(archive) = one(f, "archive") else {
        eprintln!("alloc-runner ar-unresolved: --archive is required");
        return EXIT_CANNOT_RUN;
    };
    //  --baseline is the form that needs no candidate list: it reports what
    // the splice BROKE, by requiring that the baseline archive defined the
    // symbol. --symbols is the older form and stays for the callers that know
    // exactly which names they are supplying.
    if let Some(baseline) = one(f, "baseline") {
        if one(f, "symbols").is_some() {
            eprintln!("alloc-runner ar-unresolved: give --symbols or --baseline, not both");
            return EXIT_CANNOT_RUN;
        }
        return match ar::stranded(Path::new(archive), Path::new(baseline)) {
            Ok(names) => {
                for n in &names {
                    println!("{}", n);
                }
                EXIT_OK
            }
            Err(e) => {
                eprintln!("alloc-runner ar-unresolved: {}", e);
                EXIT_CANNOT_RUN
            }
        };
    }
    let Some(syms) = one(f, "symbols") else {
        eprintln!("alloc-runner ar-unresolved: --symbols or --baseline is required");
        return EXIT_CANNOT_RUN;
    };
    let candidates: Vec<String> = syms
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if candidates.is_empty() {
        eprintln!("alloc-runner ar-unresolved: --symbols named nothing");
        return EXIT_CANNOT_RUN;
    }
    match ar::unresolved(Path::new(archive), &candidates) {
        Ok(names) => {
            for n in &names {
                println!("{}", n);
            }
            EXIT_OK
        }
        Err(e) => {
            eprintln!("alloc-runner ar-unresolved: {}", e);
            EXIT_CANNOT_RUN
        }
    }
}

fn cmd_patch_rg(f: &Flags) -> u8 {
    let Some(src) = one(f, "src") else {
        eprintln!("alloc-runner patch-rg: --src is required");
        return EXIT_CANNOT_RUN;
    };
    let root = Path::new(src);
    if !root.join("crates/core/main.rs").exists() {
        eprintln!(
            "alloc-runner patch-rg: {} does not look like a ripgrep checkout (no crates/core/main.rs)",
            src
        );
        return EXIT_CANNOT_RUN;
    }
    let before = patchrg::count_global_allocators(root);
    let shim = match (one(f, "shim-path"), one(f, "shim-feature")) {
        (Some(p), Some(feat)) => Some((p, feat)),
        (None, None) => None,
        _ => {
            eprintln!("alloc-runner patch-rg: --shim-path and --shim-feature go together");
            return EXIT_CANNOT_RUN;
        }
    };
    match patchrg::patch(root, shim) {
        Ok(r) => {
            emit(&J::obj(vec![
                ("global_allocators_before", J::U(before as u64)),
                ("stripped_items", J::U(r.stripped_items as u64)),
                ("stripped_jemalloc_dep", J::Bool(r.stripped_dep)),
                ("inserted_shim", J::Bool(r.inserted)),
                ("global_allocators_after", J::U(r.final_count as u64)),
            ]));
            EXIT_OK
        }
        Err(e) => {
            eprintln!("alloc-runner patch-rg: {}", e);
            EXIT_FAILED
        }
    }
}

fn cmd_aslr_probe(f: &Flags) -> u8 {
    let (Some(bin), Some(corpus_dir)) = (one(f, "bin"), one(f, "corpus")) else {
        eprintln!("alloc-runner aslr-probe: --bin and --corpus are required");
        return EXIT_CANNOT_RUN;
    };
    // The `nomatch` workload is used because it runs long enough to be sampled
    // and produces no output to compete with.
    let data = Path::new(corpus_dir)
        .join(corpus::DATA_SUBDIR)
        .to_string_lossy()
        .into_owned();
    let args: Vec<String> = [
        "--no-ignore",
        "--hidden",
        "--no-messages",
        "QQQQ-ZZZZ-NO-SUCH-TOKEN",
        &data,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    let runs = num(f, "runs", 6) as usize;
    match aslr::probe(Path::new(bin), &args, runs) {
        Ok(obs) => {
            emit(&obs.to_json());
            if obs.sampled == 0 {
                eprintln!(
                    "alloc-runner aslr-probe: never caught the child mapped; nothing observed"
                );
                return EXIT_CANNOT_RUN;
            }
            match one(f, "expect") {
                Some("randomised") if !obs.randomised() => {
                    eprintln!(
                        "alloc-runner aslr-probe: expected a moving base, saw {} distinct in {} samples",
                        obs.distinct(),
                        obs.sampled
                    );
                    EXIT_FAILED
                }
                Some("fixed") if obs.randomised() => {
                    eprintln!(
                        "alloc-runner aslr-probe: expected a fixed base, saw {} distinct",
                        obs.distinct()
                    );
                    EXIT_FAILED
                }
                _ => EXIT_OK,
            }
        }
        Err(e) => {
            eprintln!("alloc-runner aslr-probe: {}", e);
            EXIT_CANNOT_RUN
        }
    }
}

/// The identity gate for a `preload` cell, which cannot be the ELF read that
/// serves every other mechanism: the allocator is not in the binary.
///
///  Three pieces of evidence, and all three must hold. A configuration that
/// passes two of them is the failure mode this project exists to refuse.
///
///   1. the shared object really is the named allocator - the ordinary symbol
///      oracle, applied to the library instead of the executable;
///   2. running the real subject with `LD_PRELOAD` set, the library is mapped
///      into it - read from `/proc/<pid>/maps`, from outside, while it runs;
///   3. running it WITHOUT, the library is absent.  This is the half that
///      makes (2) mean anything: a check that says yes either way says nothing.
fn cmd_preload_check(f: &Flags) -> u8 {
    let (Some(bin), Some(so), Some(corpus_dir)) = (one(f, "bin"), one(f, "so"), one(f, "corpus"))
    else {
        eprintln!("alloc-runner preload-check: --bin, --so and --corpus are required");
        return EXIT_CANNOT_RUN;
    };
    let expect_alloc = match one(f, "expect-allocator") {
        Some(a) => a,
        None => {
            eprintln!("alloc-runner preload-check: --expect-allocator is required");
            return EXIT_CANNOT_RUN;
        }
    };

    // (1) The library is the allocator it claims to be.
    //
    //  `elf::LinkKind` has no shared-object variant, so a `.so` classifies as
    // `static-pie` (ET_DYN, no PT_INTERP). That is why the link kind is neither
    // asserted nor reported here: it would be a true-looking field with a
    // misleading value. What is asserted is the symbol evidence.
    let lib = match elf::parse(Path::new(so)) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("alloc-runner preload-check: cannot read {}: {}", so, err);
            return EXIT_CANNOT_RUN;
        }
    };
    let found = ident::detect(&lib);
    let mut reasons: Vec<String> = Vec::new();
    if !lib.had_symtab {
        reasons.push(format!(
            "{} has no .symtab (stripped): symbol evidence is unavailable, so identity is UNPROVEN",
            so
        ));
    }
    if !found.contains(&expect_alloc) {
        reasons.push(format!(
            "no symbol evidence of {} in {} (found: {})",
            expect_alloc,
            so,
            if found.is_empty() {
                "none".to_string()
            } else {
                found.join(", ")
            }
        ));
    }

    // (2) and (3). The `nomatch` shape is used for the same reason aslr-probe
    // uses it: it runs long enough to be sampled and writes nothing.
    let data = Path::new(corpus_dir)
        .join(corpus::DATA_SUBDIR)
        .to_string_lossy()
        .into_owned();
    let args: Vec<String> = [
        "--no-ignore",
        "--hidden",
        "--no-messages",
        "QQQQ-ZZZZ-NO-SUCH-TOKEN",
        &data,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    let runs = num(f, "runs", 4) as usize;

    //  The SAME path is searched for in both runs; only the environment
    // differs. See preload::probe -- an earlier draft skipped the search in the
    // control, which made "absent without LD_PRELOAD" true by construction.
    let with = match preload::probe(Path::new(bin), &args, so, true, runs) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("alloc-runner preload-check: {}", e);
            return EXIT_CANNOT_RUN;
        }
    };
    let without = match preload::probe(Path::new(bin), &args, so, false, runs) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("alloc-runner preload-check: {}", e);
            return EXIT_CANNOT_RUN;
        }
    };

    //  Never caught the subject mapped => the instrument could not look, which
    // is exit 2 and never a pass. docs/AGENTS.md
    if with.sampled == 0 || without.sampled == 0 {
        emit(&J::obj(vec![
            ("so", J::s(so)),
            ("expect_allocator", J::s(expect_alloc)),
            ("with_preload", with.to_json()),
            ("without_preload", without.to_json()),
            ("ok", J::Bool(false)),
        ]));
        eprintln!(
            "alloc-runner preload-check: never caught the subject mapped ({}/{} with, {}/{} without); nothing was observed",
            with.sampled, with.attempts, without.sampled, without.attempts
        );
        return EXIT_CANNOT_RUN;
    }

    if with.resident == 0 {
        reasons.push(format!(
            "LD_PRELOAD={} was set and the library was mapped into 0 of {} sampled runs: the loader did not take it, so the process ran the libc allocator under {}'s name",
            so, with.sampled, expect_alloc
        ));
    }
    if without.resident != 0 {
        reasons.push(format!(
            "the library was mapped in {} of {} runs with NO LD_PRELOAD set: the positive observation does not distinguish a working preload from a library that is there anyway",
            without.resident, without.sampled
        ));
    }

    let ok = reasons.is_empty();
    emit(&J::obj(vec![
        ("so", J::s(so)),
        ("expect_allocator", J::s(expect_alloc)),
        (
            "allocators_detected_in_library",
            J::arr(found.into_iter().map(J::s).collect()),
        ),
        ("library_has_symtab", J::Bool(lib.had_symtab)),
        ("with_preload", with.to_json()),
        ("without_preload", without.to_json()),
        ("ok", J::Bool(ok)),
        (
            "reasons",
            J::arr(reasons.iter().cloned().map(J::S).collect()),
        ),
    ]));
    if ok {
        EXIT_OK
    } else {
        for r in &reasons {
            eprintln!("alloc-runner preload-check: {}", r);
        }
        EXIT_FAILED
    }
}

fn cmd_workloads() -> u8 {
    emit(&J::arr(
        WORKLOADS
            .iter()
            .map(|w| {
                J::obj(vec![
                    ("name", J::s(w.name)),
                    ("why", J::s(w.why)),
                    ("args", J::arr(w.args.iter().map(|a| J::s(*a)).collect())),
                    (
                        "accept_exit",
                        J::arr(w.accept.iter().map(|c| J::I(*c as i64)).collect()),
                    ),
                ])
            })
            .collect(),
    ));
    EXIT_OK
}

fn cmd_measure(f: &Flags) -> u8 {
    let (Some(bin), Some(corpus_dir), Some(wname)) =
        (one(f, "bin"), one(f, "corpus"), one(f, "workload"))
    else {
        eprintln!("alloc-runner measure: --bin, --corpus and --workload are required");
        return EXIT_CANNOT_RUN;
    };
    let Some(w) = WORKLOADS.iter().find(|w| w.name == wname) else {
        eprintln!(
            "alloc-runner measure: unknown workload {:?}; known: {}",
            wname,
            WORKLOADS
                .iter()
                .map(|w| w.name)
                .collect::<Vec<_>>()
                .join(", ")
        );
        return EXIT_CANNOT_RUN;
    };
    if !Path::new(bin).exists() {
        eprintln!("alloc-runner measure: no such binary: {}", bin);
        return EXIT_CANNOT_RUN;
    }
    let data = Path::new(corpus_dir).join(corpus::DATA_SUBDIR);
    let onefile = data.join("d000/f0000.txt");
    if !onefile.exists() {
        eprintln!(
            "alloc-runner measure: corpus incomplete: {} missing",
            onefile.display()
        );
        return EXIT_CANNOT_RUN;
    }

    let repeat = num(f, "repeat", 10).max(1) as usize;
    //  Warm-up runs are DISCARDED, not averaged in. The first run pays for a
    // cold page cache over a 65 MB corpus, which is a filesystem measurement,
    // not an allocator one.
    let warmup = num(f, "warmup", 2) as usize;
    let timeout = num(f, "timeout", 300);

    let argv: Vec<String> = std::iter::once(bin.to_string())
        .chain(w.args.iter().map(|a| {
            a.replace("{corpus}", &data.to_string_lossy())
                .replace("{onefile}", &onefile.to_string_lossy())
        }))
        .collect();

    let extra_env: Vec<(String, String)> = f
        .get("env")
        .map(|vs| {
            vs.iter()
                .filter_map(|kv| {
                    kv.split_once('=')
                        .map(|(k, v)| (k.to_string(), v.to_string()))
                })
                .collect()
        })
        .unwrap_or_default();

    let mut samples = Vec::new();
    let mut failures = 0usize;
    for i in 0..(warmup + repeat) {
        match measure::run_once(&argv, &extra_env, None, timeout) {
            Ok(s) => {
                if i >= warmup {
                    if !s.ok(w.accept) {
                        failures += 1;
                    }
                    samples.push(s);
                } else if !s.ok(w.accept) {
                    // A warm-up that fails is still a failure; it just is not a
                    // timing sample. Reporting it keeps a configuration that
                    // only ever fails from looking like it produced no data.
                    failures += 1;
                }
            }
            Err(e) => {
                eprintln!("alloc-runner measure: {}", e);
                return EXIT_CANNOT_RUN;
            }
        }
    }

    let walls: Vec<f64> = samples
        .iter()
        .filter(|s| s.ok(w.accept))
        .map(|s| s.wall_ns as f64 / 1e9)
        .collect();
    let rss: Vec<f64> = samples
        .iter()
        .filter(|s| s.ok(w.accept))
        .map(|s| s.maxrss_kb as f64)
        .collect();

    let wall_stats = measure::stats(&walls);
    let rss_stats = measure::stats(&rss);

    emit(&J::obj(vec![
        ("workload", J::s(w.name)),
        ("binary", J::s(bin)),
        (
            "argv",
            J::arr(argv.iter().map(|a| J::s(a.clone())).collect()),
        ),
        ("repeat", J::U(repeat as u64)),
        ("warmup", J::U(warmup as u64)),
        ("failures", J::U(failures as u64)),
        ("samples_ok", J::U(walls.len() as u64)),
        (
            "wall_s",
            wall_stats.as_ref().map(|s| s.to_json()).unwrap_or(J::Null),
        ),
        (
            "maxrss_kb",
            rss_stats.as_ref().map(|s| s.to_json()).unwrap_or(J::Null),
        ),
        (
            "samples",
            J::arr(samples.iter().map(|s| s.to_json()).collect()),
        ),
    ]));

    if failures > 0 || walls.is_empty() {
        EXIT_FAILED
    } else {
        EXIT_OK
    }
}

fn cmd_archive_check(f: &Flags) -> u8 {
    let Some(archive) = one(f, "archive") else {
        eprintln!("alloc-runner archive-check: --archive is required");
        return EXIT_CANNOT_RUN;
    };
    let symbol = one(f, "symbol").unwrap_or("malloc");
    let providers = match ar::definers(Path::new(archive), symbol) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("alloc-runner archive-check: {}", e);
            return EXIT_CANNOT_RUN;
        }
    };
    let expect = num(f, "expect-providers", 1) as usize;
    let ok = providers.len() == expect;
    emit(&J::obj(vec![
        ("archive", J::s(archive)),
        ("symbol", J::s(symbol)),
        ("expect_providers", J::U(expect as u64)),
        ("found_providers", J::U(providers.len() as u64)),
        (
            "members",
            J::arr(providers.iter().map(|p| J::s(p.member.clone())).collect()),
        ),
        ("ok", J::Bool(ok)),
    ]));
    if !ok {
        eprintln!(
            "alloc-runner archive-check: {} definition(s) of {} in {}, expected {}: {:?}",
            providers.len(),
            symbol,
            archive,
            expect,
            providers.iter().map(|p| &p.member).collect::<Vec<_>>()
        );
        return EXIT_FAILED;
    }
    EXIT_OK
}

// ---------------------------------------------------------------------------

fn cmd_selftest() -> u8 {
    let mut fails = 0;
    let mut ran = 0;
    let mut skipped: Vec<String> = Vec::new();
    let mut check = |name: &str, ok: bool, detail: String| {
        println!(
            "  {}  {} {}",
            if ok { "ok  " } else { "FAIL" },
            name,
            detail
        );
        ran += 1;
        if !ok {
            fails += 1;
        }
    };

    // The generator must be a pure function of (seed, profile). If it is not,
    // two hosts cannot be compared and nothing downstream means anything.
    let a = corpus::generate(None, 42, corpus::profile("smoke").unwrap()).unwrap();
    let b = corpus::generate(None, 42, corpus::profile("smoke").unwrap()).unwrap();
    check(
        "corpus-deterministic",
        a.digest == b.digest && a.literal_lines == b.literal_lines,
        format!("digest {:016x}", a.digest),
    );

    let c = corpus::generate(None, 43, corpus::profile("smoke").unwrap()).unwrap();
    check(
        "corpus-seed-sensitive",
        a.digest != c.digest,
        format!("{:016x} vs {:016x}", a.digest, c.digest),
    );

    // A positive control for the truth itself: the smoke corpus must actually
    // contain planted needles. A generator that planted none would make every
    // "expected 0, got 0" check pass for the wrong reason.
    check(
        "corpus-plants-needles",
        a.literal_lines > 0 && a.regex_lines > 0 && a.unicode_lines > 0,
        format!(
            "literal={} regex={} unicode={}",
            a.literal_lines, a.regex_lines, a.unicode_lines
        ),
    );

    // The ELF reader must refuse a non-ELF rather than report an empty one:
    // "no allocator symbols found" and "this is not a binary" must not read
    // the same.
    check(
        "elf-rejects-non-elf",
        elf::parse_bytes(b"not an elf at all, not even close").is_err(),
        String::new(),
    );

    // And it must read the one ELF that is certainly present: itself.
    match std::env::current_exe()
        .map_err(|e| e.to_string())
        .and_then(|p| elf::parse(&p))
    {
        Ok(e) => check(
            "elf-reads-self",
            !e.syms.is_empty() || !e.had_symtab,
            format!(
                "{} {} symbols={}",
                elf::machine_name(e.machine),
                e.kind.as_str(),
                e.syms.len()
            ),
        ),
        Err(e) => check("elf-reads-self", false, e),
    }

    // The statistics must be robust where they claim to be. One wild outlier
    // moves the mean and must not move the median.
    let s = measure::stats(&[1.0, 1.0, 1.0, 1.0, 100.0]).unwrap();
    check(
        "stats-median-robust",
        (s.median - 1.0).abs() < 1e-9 && s.mean > 10.0,
        format!("median={} mean={:.1}", s.median, s.mean),
    );

    // Measurement must observe a real failure as a failure.
    match measure::run_once(
        &["/bin/sh".into(), "-c".into(), "exit 3".into()],
        &[],
        None,
        30,
    ) {
        Ok(smp) => check(
            "measure-sees-exit-code",
            smp.exit_code == 3 && smp.signal.is_none() && smp.wall_ns > 0,
            format!("exit={} wall_ns={}", smp.exit_code, smp.wall_ns),
        ),
        Err(e) => check("measure-sees-exit-code", false, e),
    }

    // ...and a signal as a signal, not as a fast run.
    match measure::run_once(
        &["/bin/sh".into(), "-c".into(), "kill -SEGV $$".into()],
        &[],
        None,
        30,
    ) {
        Ok(smp) => check(
            "measure-sees-signal",
            smp.signal == Some(libc::SIGSEGV) && !smp.ok(&[0]),
            format!("signal={:?}", smp.signal),
        ),
        Err(e) => check("measure-sees-signal", false, e),
    }

    // The timeout must fire, or a deadlocked allocator would hang the run.
    match measure::run_once(
        &["/bin/sh".into(), "-c".into(), "sleep 30".into()],
        &[],
        None,
        1,
    ) {
        Ok(smp) => check(
            "measure-timeout-kills",
            smp.signal == Some(libc::SIGKILL) && smp.wall_ns < 5_000_000_000,
            format!(
                "signal={:?} wall_s={:.2}",
                smp.signal,
                smp.wall_ns as f64 / 1e9
            ),
        ),
        Err(e) => check("measure-timeout-kills", false, e),
    }

    {
        let sym = |n: &str, defined: bool| elf::Sym {
            name: n.to_string(),
            bind: 1,
            kind: 2,
            defined,
        };
        let dynamic_baseline = |syms: Vec<elf::Sym>| elf::Elf {
            machine: 0x3e,
            kind: elf::LinkKind::Dynamic,
            interp: Some("/lib/ld-musl-x86_64.so.1".into()),
            syms,
            had_symtab: true,
        };

        // The real shape, read off that binary with nm: imports the API,
        // defines none of it.
        let good = dynamic_baseline(vec![sym("malloc", false), sym("free", false)]);
        check(
            "ident-accepts-a-dynamic-baseline",
            ident::judge(&good, "system", Some(&elf::LinkKind::Dynamic), false).ok,
            String::new(),
        );

        //  Negative control 1: a "baseline" that carries its own allocator is
        // not the distribution's allocator, however dynamic it is.
        let carries = dynamic_baseline(vec![sym("malloc", true), sym("free", true)]);
        check(
            "ident-refuses-a-dynamic-baseline-that-defines-malloc",
            !ident::judge(&carries, "system", Some(&elf::LinkKind::Dynamic), false).ok,
            String::new(),
        );

        //  Negative control 2: neither defined nor imported. Nothing will
        // resolve an allocator into this process and it is not a control.
        let neither = dynamic_baseline(vec![sym("main", true)]);
        check(
            "ident-refuses-a-dynamic-baseline-with-no-malloc-at-all",
            !ident::judge(&neither, "system", Some(&elf::LinkKind::Dynamic), false).ok,
            String::new(),
        );

        //  Negative control 3: contamination, which the new branch must not
        // have stopped checking.
        let leaked = dynamic_baseline(vec![
            sym("malloc", false),
            sym("free", false),
            sym("mi_malloc", true),
        ]);
        check(
            "ident-refuses-a-dynamic-baseline-with-a-candidate-in-it",
            !ident::judge(&leaked, "system", Some(&elf::LinkKind::Dynamic), false).ok,
            String::new(),
        );

        //  Negative control 4: THE STATIC RULE IS UNCHANGED. A static baseline
        // still has to show the libc allocator's own internals, and importing
        // malloc buys it nothing - there is no loader to satisfy the import.
        let static_no_libc = elf::Elf {
            machine: 0x3e,
            kind: elf::LinkKind::StaticPie,
            interp: None,
            syms: vec![sym("malloc", false), sym("free", false)],
            had_symtab: true,
        };
        check(
            "ident-still-requires-a-libc-allocator-in-a-static-baseline",
            !ident::judge(
                &static_no_libc,
                "system",
                Some(&elf::LinkKind::StaticPie),
                false,
            )
            .ok,
            String::new(),
        );
        let static_musl = elf::Elf {
            machine: 0x3e,
            kind: elf::LinkKind::StaticPie,
            interp: None,
            syms: vec![
                sym("malloc", true),
                sym("get_meta", true),
                sym("nontrivial_free", true),
            ],
            had_symtab: true,
        };
        check(
            "ident-accepts-a-static-baseline-with-musl-internals",
            ident::judge(
                &static_musl,
                "system",
                Some(&elf::LinkKind::StaticPie),
                false,
            )
            .ok,
            String::new(),
        );
    }

    // --- the preload residency reader ---------------------------------------
    //
    //  The whole of a preload cell's identity rests on these two functions,
    // and they read text. So they are checked against text, with the two
    // near-misses that would each turn the gate into a rubber stamp planted
    // deliberately:
    //
    //   a SUFFIX match on the library, which would let /other/dir/liballocbench.so
    //   answer for the path we actually set;
    //   an unqualified path match on the subject, which would count a
    //   non-executable mapping of the binary -- present in every run, preload or
    //   not -- as "the process is up".
    //
    //  A negative-control line is in the fixture for each, and the checks
    // assert the parser refuses them rather than merely accepting the good one.
    {
        const MAPS: &str = concat!(
            "55a4c0e00000-55a4c0e21000 r-xp 00000000 08:01 111 /out/rg\n",
            "55a4c1000000-55a4c1002000 r--p 00000000 08:01 111 /out/rg\n",
            "7f2b00000000-7f2b00040000 r-xp 00000000 08:01 222 /cache/alloc/k/lib/liballocbench.so\n",
            "7f2b00100000-7f2b00140000 r-xp 00000000 08:01 333 /usr/lib/libc.so\n",
            "7ffd00000000-7ffd00021000 rw-p 00000000 00:00 0 [stack]\n",
        );
        let want = |p: &str| vec![p.to_string()];
        check(
            "preload-maps-finds-the-exact-path",
            preload::mapping_in(MAPS, &want("/cache/alloc/k/lib/liballocbench.so"))
                .is_some_and(|l| l.contains("7f2b00000000")),
            String::new(),
        );
        //  The negative control for (2) above: a DIFFERENT directory, same
        // basename. A suffix match would say yes and the gate would pass a cell
        // whose loader took nothing.
        check(
            "preload-maps-refuses-a-same-name-elsewhere",
            preload::mapping_in(MAPS, &want("/somewhere/else/liballocbench.so")).is_none(),
            String::new(),
        );
        check(
            "preload-maps-sees-the-subject-executable",
            preload::subject_in(MAPS, "/out/rg"),
            String::new(),
        );
        //  /proc/<pid>/maps reports the RESOLVED path. Where /lib is a symlink
        // to /usr/lib, an exact match against the caller's string finds
        // nothing - which is how experiments/90- case 3 found the reader unable
        // to see a libc that is mapped into every process on the host. Both
        // forms are offered, and the match is still exact against each.
        const RESOLVED: &str =
            "7f00000000-7f00040000 r-xp 00000000 08:01 9 /usr/lib/x86_64-linux-gnu/libc.so.6\n";
        check(
            "preload-maps-matches-the-canonical-form",
            preload::mapping_in(
                RESOLVED,
                &[
                    "/lib/x86_64-linux-gnu/libc.so.6".to_string(),
                    "/usr/lib/x86_64-linux-gnu/libc.so.6".to_string(),
                ],
            )
            .is_some(),
            String::new(),
        );
        check(
            "preload-maps-still-refuses-an-unrelated-canonical-path",
            preload::mapping_in(RESOLVED, &want("/usr/lib/x86_64-linux-gnu/libm.so.6")).is_none(),
            String::new(),
        );

        // A maps file with the binary present but NOT executable is a process
        // that has not reached its text yet; treating it as up would make the
        // library's absence look like a verdict rather than a miss.
        const NO_TEXT: &str =
            "55a4c1000000-55a4c1002000 r--p 00000000 08:01 111 /out/rg\n[stack]\n";
        check(
            "preload-maps-refuses-a-non-executable-subject",
            !preload::subject_in(NO_TEXT, "/out/rg"),
            String::new(),
        );
    }

    // --- ar::unresolved, the question libc-surgery asks after the splice ----
    //
    //  Needs a C compiler, because the input is a real relocatable object: one
    // that CALLS __libc_malloc without defining it, which is precisely musl's
    // shape after its allocator members are deleted. Where cc is absent the
    // check is reported as SKIPPED, never as passed -- "I could not look" and
    // "I looked and found nothing" are different results (docs/AGENTS.md).
    match ar_unresolved_selftest() {
        Ok(Some((missing_before, missing_after))) => {
            check(
                "ar-unresolved-finds-a-stranded-alias",
                missing_before == vec!["__libc_malloc".to_string()],
                format!("{:?}", missing_before),
            );
            check(
                "ar-unresolved-clears-once-supplied",
                missing_after.is_empty(),
                format!("{:?}", missing_after),
            );
        }
        Ok(None) => skipped.push("ar-unresolved (no C compiler on PATH)".into()),
        Err(e) => check("ar-unresolved-finds-a-stranded-alias", false, e),
    }

    // --- ar::stranded, the same question WITHOUT a candidate list ----------
    //
    //  The list is what failed. `libc-surgery.sh` asks about four hard-coded
    // aliases, which is the standing-list defect this project criticises the
    // prior art for, one level up: Chimera's musl strands
    // `__malloc_tls_default`, which is on nobody's list.
    match ar_stranded_selftest() {
        Ok(Some((broke, fine))) => {
            check(
                "ar-stranded-finds-what-the-splice-broke",
                broke == vec!["__malloc_tls_default".to_string()],
                format!("{:?}", broke),
            );
            //  THE FALSE-POSITIVE CASE. `__never_defined_anywhere` is
            // undefined in the spliced archive AND in the baseline, exactly
            // like a compiler builtin. Reporting it would make this check
            // refuse every working libc.a there is.
            check(
                "ar-stranded-ignores-what-was-never-defined",
                !broke.iter().any(|n| n == "__never_defined_anywhere"),
                format!("{:?}", broke),
            );
            check(
                "ar-stranded-clears-when-the-replacement-supplies-it",
                fine.is_empty(),
                format!("{:?}", fine),
            );
        }
        Ok(None) => skipped.push("ar-stranded (no C compiler on PATH)".into()),
        Err(e) => check("ar-stranded-finds-what-the-splice-broke", false, e),
    }

    // An archive with no members references nothing, and that is not an error.
    let empty = std::env::temp_dir().join(format!("alloc-runner-empty-{}.a", std::process::id()));
    let _ = std::fs::write(&empty, b"!<arch>\n");
    let r = ar::unresolved(&empty, &["__libc_malloc".to_string()]);
    check(
        "ar-unresolved-empty-archive-is-empty",
        matches!(&r, Ok(v) if v.is_empty()),
        format!("{:?}", r.as_ref().map(|v| v.len())),
    );
    let _ = std::fs::remove_file(&empty);

    // ...and a file that is not an archive must be refused, not read as empty.
    let notar = std::env::temp_dir().join(format!("alloc-runner-notar-{}.a", std::process::id()));
    let _ = std::fs::write(&notar, b"this is not an ar archive");
    let r = ar::unresolved(&notar, &["__libc_malloc".to_string()]);
    check(
        "ar-unresolved-rejects-non-archive",
        r.is_err(),
        String::new(),
    );
    let _ = std::fs::remove_file(&notar);

    for s in &skipped {
        println!("  SKIP  {}", s);
    }
    //  Derived, never typed. The previous version printed a literal 9 while
    // running nine checks; the next check added would have made it a lie.
    println!(
        "alloc-runner selftest: {} check(s), {} failure(s), {} skipped.",
        ran,
        fails,
        skipped.len()
    );
    if fails == 0 {
        EXIT_OK
    } else {
        EXIT_FAILED
    }
}

/// What `ar_unresolved_selftest` reports: the stranded names before the
/// forwarder is added, and after. `None` means there was no C compiler to build
/// the fixtures with.
type UnresolvedProbe = Option<(Vec<String>, Vec<String>)>;

/// Build two real objects and ask `ar::unresolved` about them.
///
/// Returns `Ok(None)` when there is no C compiler, so the caller can report a
/// skip. The first archive is musl's shape after the surgery -- a caller of
/// `__libc_malloc` and a `malloc` that does not define it. The second adds the
/// forwarder `libc-surgery.sh` synthesises.
fn ar_unresolved_selftest() -> Result<UnresolvedProbe, String> {
    let cc = ["cc", "gcc", "clang"].into_iter().find(|c| {
        std::process::Command::new(c)
            .arg("--version")
            .output()
            .is_ok()
    });
    let Some(cc) = cc else { return Ok(None) };

    let dir = std::env::temp_dir().join(format!("alloc-runner-ar-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let write = |name: &str, body: &str| -> Result<std::path::PathBuf, String> {
        let p = dir.join(name);
        std::fs::write(&p, body).map_err(|e| e.to_string())?;
        Ok(p)
    };
    let compile = |src: &std::path::Path| -> Result<std::path::PathBuf, String> {
        let obj = src.with_extension("o");
        let out = std::process::Command::new(cc)
            .args(["-O0", "-c"])
            .arg(src)
            .arg("-o")
            .arg(&obj)
            .output()
            .map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        Ok(obj)
    };

    // musl's surviving object: calls the internal alias, defines it nowhere.
    let caller = compile(&write(
        "caller.c",
        "extern void *__libc_malloc(unsigned long);\nvoid *use(void){return __libc_malloc(8);}\n",
    )?)?;
    // the replacement allocator: defines malloc, not the alias.
    let alloc = compile(&write(
        "alloc.c",
        "void *malloc(unsigned long n){(void)n;return 0;}\n",
    )?)?;
    // what the surgery synthesises.
    let fwd = compile(&write(
        "fwd.c",
        "void *malloc(unsigned long);\nvoid *__libc_malloc(unsigned long n){return malloc(n);}\n",
    )?)?;

    let ar_of = |name: &str, objs: &[&std::path::Path]| -> Result<std::path::PathBuf, String> {
        let a = dir.join(name);
        let _ = std::fs::remove_file(&a);
        let out = std::process::Command::new("ar")
            .arg("rcs")
            .arg(&a)
            .args(objs)
            .output()
            .map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        Ok(a)
    };

    let cands = vec!["__libc_malloc".to_string(), "__libc_free".to_string()];
    let before = ar::unresolved(&ar_of("before.a", &[&caller, &alloc])?, &cands)?;
    let after = ar::unresolved(&ar_of("after.a", &[&caller, &alloc, &fwd])?, &cands)?;
    let _ = std::fs::remove_dir_all(&dir);
    Ok(Some((before, after)))
}

/// What `ar_stranded_selftest` reports: what the splice broke, and the two
/// things it must NOT report. `None` means there was no C compiler.
type StrandedProbe = Option<(Vec<String>, Vec<String>)>;

///  THE CASE THAT MATTERS IS THE FALSE POSITIVE. `ar::stranded` is allowed to
/// answer without a candidate list only because the baseline filters out every
/// symbol `libc.a` never defined in the first place -- compiler builtins,
/// `__stack_chk_fail`. So the fixture below plants BOTH: a symbol the deletion
/// really stranded (`__malloc_tls_default`, Chimera's shape) and a symbol that
/// is undefined in the spliced archive AND in the baseline
/// (`__never_defined_anywhere`). The first must be reported and the second must
/// not, or the check is one that refuses working archives.
///
///  And the second half plants the opposite defect: an archive spliced with a
/// replacement that DOES supply the stranded symbol must come back empty, so a
/// check that always finds something is caught too.
fn ar_stranded_selftest() -> Result<StrandedProbe, String> {
    let cc = ["cc", "gcc", "clang"].into_iter().find(|c| {
        std::process::Command::new(c)
            .arg("--version")
            .output()
            .is_ok()
    });
    let Some(cc) = cc else { return Ok(None) };

    let dir = std::env::temp_dir().join(format!("alloc-runner-strand-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let write = |name: &str, body: &str| -> Result<std::path::PathBuf, String> {
        let p = dir.join(name);
        std::fs::write(&p, body).map_err(|e| e.to_string())?;
        Ok(p)
    };
    let compile = |src: &std::path::Path| -> Result<std::path::PathBuf, String> {
        let obj = src.with_extension("o");
        let out = std::process::Command::new(cc)
            .args(["-O0", "-c"])
            .arg(src)
            .arg("-o")
            .arg(&obj)
            .output()
            .map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        Ok(obj)
    };

    // The allocator member the surgery deletes: defines malloc AND a data
    // symbol the threading code reaches for. Chimera's `mimalloc.o` in little.
    let victim = compile(&write(
        "victim.c",
        "void *__malloc_tls_default;\nvoid *malloc(unsigned long n){(void)n;return 0;}\n",
    )?)?;
    // An unrelated survivor that references it -- and also references something
    // NOTHING in either archive defines.
    let survivor = compile(&write(
        "survivor.c",
        "extern void *__malloc_tls_default;\nextern void __never_defined_anywhere(void);\n\
         void *tls(void){__never_defined_anywhere();return __malloc_tls_default;}\n",
    )?)?;
    // A replacement that supplies only malloc, and one that supplies the data
    // symbol too.
    let repl = compile(&write(
        "repl.c",
        "void *malloc(unsigned long n){(void)n;return (void*)0;}\n",
    )?)?;
    let repl_full = compile(&write(
        "repl_full.c",
        "void *__malloc_tls_default;\nvoid *malloc(unsigned long n){(void)n;return (void*)0;}\n",
    )?)?;

    let ar_of = |name: &str, objs: &[&std::path::Path]| -> Result<std::path::PathBuf, String> {
        let a = dir.join(name);
        let _ = std::fs::remove_file(&a);
        let out = std::process::Command::new("ar")
            .arg("rcs")
            .arg(&a)
            .args(objs)
            .output()
            .map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        Ok(a)
    };

    let baseline = ar_of("baseline.a", &[&victim, &survivor])?;
    let broke = ar::stranded(&ar_of("broke.a", &[&survivor, &repl])?, &baseline)?;
    let fine = ar::stranded(&ar_of("fine.a", &[&survivor, &repl_full])?, &baseline)?;
    let _ = std::fs::remove_dir_all(&dir);
    Ok(Some((broke, fine)))
}
