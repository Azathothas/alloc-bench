//! The allocator-identity oracle.
//!
//! -- THE DEFECT THIS EXISTS TO CATCH ----------------------------------------
//!
//!  A benchmark that cannot tell whether the allocator it names is actually
//! in the binary will publish the system allocator's numbers under seven
//! different names and rank them against each other. That is not hypothetical:
//! upstream mimalloc-bench issues 245 and 247 report exactly it - a missing
//! allocator library produced a full, plausible, green results table
//! (https://github.com/daanx/mimalloc-bench, commit
//! 3ad2732048312b0cc472b60302ff120f02ee9558, api/issues.json).
//!
//!  So identity is established by reading the ELF, before any timing happens.
//! Not from the build log, not from a flag the build was *asked* to use, and
//! not from the program's own report.
//!
//!  What this can and cannot prove. Finding an allocator's internal symbols
//! proves its code was linked in. It does not by itself prove every allocation
//! flows through it. The second half of that is the negative control below:
//! for a replacement build, the *displaced* allocator's implementation must be
//! ABSENT. Both together are strong; either alone is not.

use crate::elf::{Elf, LinkKind};
use crate::json::J;

pub struct Signature {
    pub id: &'static str,
    /// Symbols that must all be present. Chosen to be implementation
    /// internals rather than the public API where possible, because a public
    /// name can be an undefined reference in a binary that never linked the
    /// implementation.
    pub required: &'static [&'static str],
    /// At least one of these must be present.
    pub any_of: &'static [&'static str],
    /// At least one symbol STARTING WITH one of these satisfies `any_of` too.
    ///
    ///  Exists for C++ allocators in OVERRIDE mode, where the prefixed public
    /// API this oracle usually keys on does not exist: snmalloc's mode switch is
    /// `SNMALLOC_STATIC_LIBRARY_PREFIX`, and in override mode it is empty, so
    /// `sn_malloc` and friends are simply absent from a binary that genuinely
    /// contains snmalloc.
    ///
    ///  Only Itanium-mangled namespaces belong here. They are length-prefixed
    /// (`_ZN8snmalloc` is the 8-character name `snmalloc` and can be nothing
    /// else), which is what makes a prefix match as specific as an exact one.
    /// A bare word is not: `chacha_` was rejected as evidence for
    /// hardened_malloc because ripgrep's own Rust dependency defines
    /// `chacha_block`.
    pub any_prefix: &'static [&'static str],
}

pub const SIGNATURES: &[Signature] = &[
    Signature {
        id: "mimalloc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "mi_malloc",
            "mi_heap_malloc",
            "mi_option_get",
            "_mi_page_malloc",
            "mi_free",
        ],
    },
    Signature {
        id: "jemalloc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "je_mallocx",
            "mallocx",
            "je_malloc_conf",
            "malloc_conf",
            "je_arena_boot",
            "je_sdallocx",
            "sdallocx",
        ],
    },
    Signature {
        id: "snmalloc",
        required: &[],
        any_prefix: &["_ZN8snmalloc", "_ZNK8snmalloc"],
        any_of: &["sn_malloc", "sn_free", "snmalloc_alloc", "sn_realloc"],
    },
    Signature {
        id: "rpmalloc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "rpmalloc",
            "rpmalloc_initialize",
            "rpfree",
            "rpaligned_alloc",
        ],
    },
    Signature {
        id: "hardened_malloc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            // Prefixed build (-DH_MALLOC_PREFIX), which is what `rust-global`
            // links.
            "h_malloc",
            "h_free",
            "h_malloc_object_size",
            "h_realloc",
            "malloc_object_size_fast",
            "memory_protect_rw_metadata",
            "get_metadata_key",
        ],
    },
    Signature {
        id: "mesh",
        // Mesh is C++ and its symbols arrive mangled; `mesh` appears in the
        // mangled namespace component as `4mesh`.
        required: &[],
        any_prefix: &[],
        any_of: &["_ZN4mesh11runtimeInstEv", "mesh_malloc"],
    },
    Signature {
        id: "tcmalloc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "TCMallocInternalMalloc",
            "TCMallocInternalFree",
            "MallocExtension_Internal_GetNumericProperty",
        ],
    },
];

/// Symbols that identify the *libc's own* allocator implementation. Used as
/// the negative control for a replacement build: after libc surgery, none of
/// these may survive.
pub const LIBC_ALLOCATOR_SIGNATURES: &[Signature] = &[
    Signature {
        id: "musl",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "__libc_malloc_impl",
            "__malloc_donate",
            "alloc_meta",
            "get_meta",
            "nontrivial_free",
        ],
    },
    Signature {
        id: "glibc",
        required: &[],
        any_prefix: &[],
        any_of: &[
            "_int_malloc",
            "_int_free",
            "ptmalloc_init",
            "tcache_init",
            "sysmalloc",
            "arena_get2",
        ],
    },
];

pub fn detect(e: &Elf) -> Vec<&'static str> {
    let mut found = Vec::new();
    for s in SIGNATURES {
        let req = s.required.iter().all(|n| e.has_symbol(n));
        let any = (s.any_of.is_empty() && s.any_prefix.is_empty())
            || s.any_of.iter().any(|n| e.has_symbol(n))
            || s.any_prefix.iter().any(|p| e.has_symbol_prefixed(p));
        if req && any {
            found.push(s.id);
        }
    }
    found
}

pub fn detect_libc_allocator(e: &Elf) -> Vec<&'static str> {
    let mut found = Vec::new();
    for s in LIBC_ALLOCATOR_SIGNATURES {
        //  `any_prefix` IS HONOURED HERE TOO, and this line is the finding of a
        // door sweep rather than of writing it. `any_prefix` was added for
        // `detect` and this function was left reading `any_of` alone -- a field
        // that one of its two consumers silently drops. Both entries below carry
        // an empty `any_prefix` today so nothing was wrong, but this is the
        // NEGATIVE CONTROL: a later session adding a mangled-namespace prefix to
        // the musl or glibc signature would have got a control that never fires,
        // and a replacement build would pass with the displaced allocator still
        // in it. That is the exact failure §2.2 exists to prevent.
        if s.any_of.iter().any(|n| e.has_symbol(n))
            || s.any_prefix.iter().any(|p| e.has_symbol_prefixed(p))
        {
            found.push(s.id);
        }
    }
    found
}

#[derive(Debug)]
pub struct Verdict {
    pub ok: bool,
    pub reasons: Vec<String>,
}

/// Decide whether `e` really is the configuration it claims to be.
///
/// `expect_allocator` is the allocator id (`system` for the baseline),
/// `expect_kind` the link kind the build profile asked for, and
/// `replacement` whether the integration mechanism claims to have *displaced*
/// the libc allocator (libc-surgery / link-override) rather than merely added
/// one alongside it (rust-global).
pub fn judge(
    e: &Elf,
    expect_allocator: &str,
    expect_kind: Option<&LinkKind>,
    replacement: bool,
) -> Verdict {
    let mut reasons = Vec::new();
    let found = detect(e);
    let libc_alloc = detect_libc_allocator(e);

    if let Some(k) = expect_kind {
        if &e.kind != k {
            reasons.push(format!(
                "link kind is {} but the profile asked for {}",
                e.kind.as_str(),
                k.as_str()
            ));
        }
    }

    //  A stripped binary has no .symtab, so an absence proves nothing. Saying
    // so is the difference between "the allocator is not there" and "this
    // instrument could not look". They are not the same and must not read the
    // same.
    if !e.had_symtab {
        reasons.push(
            "binary has no .symtab (stripped): symbol evidence is unavailable, so identity is UNPROVEN"
                .to_string(),
        );
        return Verdict { ok: false, reasons };
    }

    if expect_allocator == "system" {
        // The control. It must contain the libc allocator and none of the
        // candidates. A candidate here means the image leaked one in - which
        // is precisely what happens if libc surgery from another cell was not
        // isolated, and it would silently make the baseline fast.
        if !found.is_empty() {
            reasons.push(format!(
                "baseline binary contains candidate allocator(s): {}. The control is contaminated.",
                found.join(", ")
            ));
        }
        if e.kind == LinkKind::Dynamic {
            for sym in ["malloc", "free"] {
                if e.defines(sym) {
                    reasons.push(format!(
                        "dynamic baseline DEFINES {} in the executable; a control that carries its own allocator is not the distribution's allocator",
                        sym
                    ));
                } else if !e.imports(sym) {
                    reasons.push(format!(
                        "dynamic baseline neither defines nor imports {}; it cannot be getting the libc allocator at load time and this binary is not the control it claims to be",
                        sym
                    ));
                }
            }
            if e.interp.is_none() {
                reasons.push(
                    "dynamic baseline has no PT_INTERP, so no loader will resolve its allocator"
                        .to_string(),
                );
            }
        } else if libc_alloc.is_empty() {
            reasons.push(
                "baseline binary shows no libc allocator implementation; expected musl or glibc"
                    .to_string(),
            );
        }
    } else {
        if !found.contains(&expect_allocator) {
            reasons.push(format!(
                "no symbol evidence of {} in the binary (found: {})",
                expect_allocator,
                if found.is_empty() {
                    "none".to_string()
                } else {
                    found.join(", ")
                }
            ));
        }
        let extra: Vec<_> = found.iter().filter(|f| **f != expect_allocator).collect();
        if !extra.is_empty() {
            reasons.push(format!(
                "binary also contains other candidate allocator(s): {:?}. Two allocators in one binary is not the configuration under test.",
                extra
            ));
        }
        if replacement && !libc_alloc.is_empty() {
            // The negative control for a replacement build.
            //
            //  IT IS A STATIC-BINARY CONTROL, and says nothing about a dynamic
            // one: in a dynamic binary the displaced allocator would not be in
            // the executable either way, so an empty `libc_allocator_detected`
            // is not evidence there. That is not a hole today - `libc-surgery`
            // and `link-override` rewrite or reorder `libc.a`, which a dynamic
            // link never reads, and no suite pairs them with the `dynamic`
            // profile - and if one ever did, the `found` check above refuses
            // the cell anyway, because the allocator would not be in the binary
            // at all.  A later session adding such a cell must not read this
            // control as having passed it.
            reasons.push(format!(
                "replacement build still contains the {} allocator implementation: the displaced allocator was not removed, so which one serves malloc is decided by link order rather than by this configuration",
                libc_alloc.join(", ")
            ));
        }
    }

    Verdict {
        ok: reasons.is_empty(),
        reasons,
    }
}

pub fn report_json(e: &Elf, verdict: &Verdict) -> J {
    J::obj(vec![
        ("machine", J::s(crate::elf::machine_name(e.machine))),
        ("link_kind", J::s(e.kind.as_str())),
        (
            "interp",
            match &e.interp {
                Some(i) => J::s(i.clone()),
                None => J::Null,
            },
        ),
        ("has_symtab", J::Bool(e.had_symtab)),
        ("symbols_total", J::U(e.syms.len() as u64)),
        (
            "allocators_detected",
            J::arr(detect(e).into_iter().map(J::s).collect()),
        ),
        (
            "libc_allocator_detected",
            J::arr(detect_libc_allocator(e).into_iter().map(J::s).collect()),
        ),
        ("ok", J::Bool(verdict.ok)),
        (
            "reasons",
            J::arr(verdict.reasons.iter().cloned().map(J::S).collect()),
        ),
    ])
}
