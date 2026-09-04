//! Was the preloaded allocator actually in the process?
//!
//! -- WHY THIS EXISTS AND WHY IT IS NOT `identify` ---------------------------
//!
//!  **A preload cell's identity cannot be established by reading the
//! executable**, because the allocator is not in it. The binary is an ordinary
//! system build; the allocator arrives at load time and leaves no trace in the
//! ELF. So the one check this project relies on - read the file, decide what is
//! in it - has nothing to read.
//!
//!  That is not a small gap. It is *precisely* the upstream defect this
//! project was built against (`docs/AGENTS.md` §2.2, mimalloc-bench issues 245
//! and 247): a missing allocator library produced a full, plausible, green
//! results table. Under `LD_PRELOAD` a missing, unreadable, ABI-wrong or
//! silently-declined library does not fail - the loader shrugs and the process
//! runs the libc allocator, at libc speed, filed under the other allocator's
//! name.
//!
//!  So the evidence is taken from **outside the process, while it runs**: the
//! parent forks the real subject with `LD_PRELOAD` set and reads
//! `/proc/<pid>/maps`. A mapping backed by that file is the loader's own record
//! that it mapped it. The subject is never asked.
//!
//!  AND A POSITIVE ALONE IS NOT ENOUGH. `probe` is run twice: once with the
//! variable and once without. If the library shows up in the control run too,
//! the match means something other than "the preload worked" - a stale path
//! match, the wrong process, a sampler bug - and the check must not pass. The
//! pair is the evidence; either half alone is a coincidence.
//!
//!  WHAT THIS STILL DOES NOT PROVE. That the mapping served the allocations.
//! Interposition could be defeated by a binary that resolved `malloc` before
//! the preload (it cannot; the loader orders preloads first) or by a library
//! that maps and exports nothing (`finish_so` in allocators/lib.sh asserts the
//! dynamic export separately). Together those two are strong. Neither alone is.

use crate::json::J;
use std::ffi::CString;
use std::fs;
use std::path::Path;

pub fn mapping_in(maps: &str, want: &[String]) -> Option<String> {
    for line in maps.lines() {
        let path = line.rsplit_once(' ').map(|(_, p)| p.trim()).unwrap_or("");
        if want.iter().any(|w| path == w) {
            return Some(line.trim().to_string());
        }
    }
    None
}

/// The caller's path plus its canonical form, de-duplicated.
pub fn candidates(want: &str) -> Vec<String> {
    let mut v = vec![want.to_string()];
    if let Ok(c) = std::fs::canonicalize(want) {
        let c = c.to_string_lossy().into_owned();
        if c != want {
            v.push(c);
        }
    }
    v
}

/// Whether the process is far enough along to be worth judging: its own
/// executable image is mapped.
///
///  Without this the absence of the library is ambiguous between "the loader
/// declined it" and "the parent looked before `execve` completed", and those
/// must not read the same. `aslr.rs` learned the same lesson: a miss is
/// recorded as a miss, never as a negative result.
pub fn subject_in(maps: &str, bin: &str) -> bool {
    maps.lines().any(|line| {
        let path = line.rsplit_once(' ').map(|(_, p)| p.trim()).unwrap_or("");
        (path == bin || path.ends_with(bin))
            && line
                .split_whitespace()
                .nth(1)
                .is_some_and(|p| p.contains('x'))
    })
}

///  ONE READ, and both questions answered from it.
///
///  An earlier version read `/proc/<pid>/maps` twice - once to decide the
/// subject was up, then again to look for the library - while a comment three
/// lines above claimed the opposite. The subject here runs for milliseconds, so
/// the second read usually landed after it had exited, returned `Err`, and the
/// library was reported absent **in every case, including the one where it was
/// certainly there**. Measured by `experiments/90-preload-residency.sh` case 1,
/// which failed on a library the loader had plainly taken. A comment describing
/// what the code should do is not a test that it does.
fn sample(pid: i32, bin: &str, want: &[String]) -> Option<(bool, Option<String>)> {
    let maps = fs::read_to_string(format!("/proc/{}/maps", pid)).ok()?;
    let up = subject_in(&maps, bin);
    let hit = if up { mapping_in(&maps, want) } else { None };
    Some((up, hit))
}

pub struct Observation {
    pub attempts: usize,
    /// Runs in which the subject's own image was seen mapped - i.e. the
    /// sampler worked at all.
    pub sampled: usize,
    /// Runs in which the preload library was seen mapped.
    pub resident: usize,
    /// The first matching `/proc/<pid>/maps` line, kept verbatim as evidence.
    pub evidence: Option<String>,
}

impl Observation {
    pub fn to_json(&self) -> J {
        J::obj(vec![
            ("attempts", J::U(self.attempts as u64)),
            ("subject_sampled", J::U(self.sampled as u64)),
            ("library_resident", J::U(self.resident as u64)),
            (
                "map_line",
                match &self.evidence {
                    Some(l) => J::s(l.clone()),
                    None => J::Null,
                },
            ),
        ])
    }
}

/// Run `bin args…` `runs` times and report how often `want` was mapped into the
/// child. `set_preload` decides whether `LD_PRELOAD=want` is in the child's
/// environment.
///
///  `want` IS LOOKED FOR IN BOTH CASES, and separating it from `set_preload`
/// is the whole point of the parameter existing. An earlier draft took a single
/// `Option<&str>` and skipped the maps search when it was `None` - which made
/// the control run report `library_resident: 0` **by construction**, so the
/// "and it is absent without LD_PRELOAD" assertion could not have failed for any
/// input whatsoever. A control that cannot fail is not a control; it is a
/// sentence in a report. Caught by reading this file before a cell was run
/// against it.
pub fn probe(
    bin: &Path,
    args: &[String],
    want: &str,
    set_preload: bool,
    runs: usize,
) -> Result<Observation, String> {
    let bin_s = bin.to_string_lossy().to_string();

    let argv: Vec<String> = std::iter::once(bin_s.clone())
        .chain(args.iter().cloned())
        .collect();
    let c_argv: Vec<CString> = argv
        .iter()
        .map(|a| CString::new(a.as_bytes()).map_err(|_| "argv NUL".to_string()))
        .collect::<Result<_, _>>()?;
    let mut argv_ptrs: Vec<*const libc::c_char> = c_argv.iter().map(|s| s.as_ptr()).collect();
    argv_ptrs.push(std::ptr::null());

    //  The environment is built BEFORE the fork. Between fork and exec only
    // async-signal-safe calls are legal, and this is the same rule measure.rs
    // states at its own fork.
    let mut env_pairs: Vec<CString> = Vec::new();
    for (k, v) in std::env::vars() {
        if k == "LD_PRELOAD" {
            continue; // never inherit one; this probe decides
        }
        env_pairs.push(CString::new(format!("{}={}", k, v)).map_err(|_| "env NUL".to_string())?);
    }
    if set_preload {
        env_pairs
            .push(CString::new(format!("LD_PRELOAD={}", want)).map_err(|_| "env NUL".to_string())?);
    }
    let mut env_ptrs: Vec<*const libc::c_char> = env_pairs.iter().map(|s| s.as_ptr()).collect();
    env_ptrs.push(std::ptr::null());

    let devnull = CString::new("/dev/null").unwrap();
    let wanted = candidates(want);

    let mut sampled = 0usize;
    let mut resident = 0usize;
    let mut evidence: Option<String> = None;

    for _ in 0..runs {
        let pid = unsafe { libc::fork() };
        if pid < 0 {
            return Err("fork failed".into());
        }
        if pid == 0 {
            unsafe {
                let fd = libc::open(devnull.as_ptr(), libc::O_WRONLY);
                if fd >= 0 {
                    libc::dup2(fd, 1);
                    libc::dup2(fd, 2);
                    if fd > 2 {
                        libc::close(fd);
                    }
                }
                libc::execve(argv_ptrs[0], argv_ptrs.as_ptr(), env_ptrs.as_ptr());
                libc::_exit(127);
            }
        }

        //  POLL UNTIL THE LIBRARY APPEARS OR THE CHILD EXITS -- do NOT stop
        // as soon as the subject's own image is mapped.
        //
        //  That was the previous version and it could never see anything.
        // The KERNEL maps the executable and the ELF interpreter at `execve`;
        // every shared library, `LD_PRELOAD` included, is mapped afterwards by
        // ld.so as it runs. So the first read in which the subject's text
        // exists is the earliest possible moment and is systematically BEFORE
        // the loader has done its work. `experiments/90-preload-residency.sh`
        // caught it by reporting `resident 0` for glibc itself -- a library
        // mapped into every process on the host.
        //
        //  So the question asked here is "did this path ever appear in the
        // process's map", and the loop ends on the answer or on the process.
        let mut saw_subject = false;
        for _ in 0..20_000 {
            //  The library is searched for UNCONDITIONALLY. The control run
            // looks for exactly the same path and must come back with nothing;
            // skipping the search when LD_PRELOAD is unset would make that
            // answer arithmetic rather than a measurement.
            if let Some((up, hit)) = sample(pid, &bin_s, &wanted) {
                if up {
                    saw_subject = true;
                }
                if let Some(line) = hit {
                    resident += 1;
                    if evidence.is_none() {
                        evidence = Some(line);
                    }
                    break;
                }
            }
            //  The child exiting is a real end to the search, and a different
            // one from running out of poll iterations. Reaped here so the
            // blocking wait below is a no-op rather than an error.
            let mut st = 0;
            if unsafe { libc::waitpid(pid, &mut st, libc::WNOHANG) } == pid {
                break;
            }
            let ts = libc::timespec {
                tv_sec: 0,
                tv_nsec: 100_000,
            };
            unsafe { libc::nanosleep(&ts, std::ptr::null_mut()) };
        }
        if saw_subject {
            sampled += 1;
        }
        let mut status = 0;
        unsafe { libc::waitpid(pid, &mut status, 0) };
    }

    Ok(Observation {
        attempts: runs,
        sampled,
        resident,
        evidence,
    })
}
