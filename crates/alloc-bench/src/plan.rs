//! Expand the matrix into cells, and decide which of them can exist.

use crate::model::*;
use std::collections::BTreeMap;

///  EVERY musl DISTRIBUTION MUST BE NAMED HERE. The fallback is `glibc`, so a
/// musl distribution added to the matrix and forgotten here is silently planned
/// as glibc - and its `libc-surgery` cells, which glibc cannot support, would be
/// marked unsupported for the wrong reason while its identity gate looked for
/// the wrong negative control.
pub fn libc_for(distro: &str) -> &'static str {
    match distro {
        "alpine" | "wolfi" | "void" => "musl",
        _ => "glibc",
    }
}

/// Which of a suite's requested variants this allocator can actually be built
/// in, in the suite's order, always including `default`.
///
///  The control is the case that shapes this. A `hardening-variants` suite
/// asks for `["default", "light"]` and names `system` alongside
/// `hardened_malloc`; `system` declares no variants, so it yields one control
/// cell rather than a `system-light` that no recipe could build and that would
/// leave the `light` row with nothing to be a ratio against.
pub fn applicable_variants(spec: &AllocatorSpec, wanted: &[String]) -> Vec<String> {
    if wanted.is_empty() {
        return vec![DEFAULT_VARIANT.to_string()];
    }
    let declared = spec.variants.as_deref().unwrap_or(&[]);
    let mut out: Vec<String> = Vec::new();
    for w in wanted {
        let ok = w == DEFAULT_VARIANT || declared.iter().any(|d| d == w);
        if ok && !out.iter().any(|o| o == w) {
            out.push(w.clone());
        }
    }
    if out.is_empty() {
        out.push(DEFAULT_VARIANT.to_string());
    }
    out
}

/// Arch publishes no aarch64 image. Rather than silently building something
/// else and calling it `archlinux`, the distribution is RENAMED for that
/// architecture, so no table can merge two distributions under one label.
pub fn effective_distro(distro: &str, arch: &str) -> String {
    if distro == "archlinux" && arch != "x86_64" {
        "archlinuxarm".to_string()
    } else {
        distro.to_string()
    }
}

pub struct Planner<'a> {
    pub manifest: &'a Manifest,
    pub matrix: &'a MatrixFile,
}

impl<'a> Planner<'a> {
    fn spec(&self, id: &str) -> Option<&AllocatorSpec> {
        self.manifest.allocators.iter().find(|a| a.id == id)
    }

    fn expand_allocators(&self, list: &[String]) -> Vec<String> {
        if list.iter().any(|s| s == "*") {
            self.manifest
                .allocators
                .iter()
                .map(|a| a.id.clone())
                .collect()
        } else {
            list.to_vec()
        }
    }

    /// Expand the named suites. `suites` may contain `all`.
    ///
    /// De-duplication is by cell id: two suites asking for the same
    /// configuration must produce ONE experiment, or the same binary would be
    /// measured twice and appear as two rows.
    pub fn plan(&self, suites: &[String]) -> Result<Vec<Cell>, String> {
        let wanted: Vec<&Suite> = if suites.iter().any(|s| s == "all") {
            self.matrix.suites.iter().collect()
        } else {
            let mut v = Vec::new();
            for want in suites {
                let s = self
                    .matrix
                    .suites
                    .iter()
                    .find(|s| &s.id == want)
                    .ok_or_else(|| {
                        format!(
                            "unknown suite {:?}; known: {}",
                            want,
                            self.matrix
                                .suites
                                .iter()
                                .map(|s| s.id.as_str())
                                .collect::<Vec<_>>()
                                .join(", ")
                        )
                    })?;
                v.push(s);
            }
            v
        };

        let mut seen: BTreeMap<String, Cell> = BTreeMap::new();
        for suite in wanted {
            //  A `profiles_by_arch` key naming an architecture this suite does
            // not run is SILENTLY IGNORED otherwise, and the failure is
            // invisible: write `arm64` for `aarch64` and `core` goes back to
            // planning `static-pie-lto` on aarch64, where every cell fails the
            // identity gate -- the exact state this key was added to fix. Found
            // by a door sweep, not by writing it.
            for arch in suite.profiles_by_arch.keys() {
                if !suite.arches.contains(arch) {
                    return Err(format!(
                        "suite {:?} has profiles_by_arch for {:?}, which is not in its \
                         arches ({:?}) -- a typo here is silent, so it is an error",
                        suite.id, arch, suite.arches
                    ));
                }
            }
            //  Same class of silent failure, one dimension over: a suite
            // asking for variant "ligth" would intersect to nothing for every
            // allocator and quietly expand to the default-only matrix, so the
            // suite would run and measure the wrong thing without a word. Each
            // name must be declared by some allocator the suite actually names.
            for variant in &suite.variants {
                if variant == DEFAULT_VARIANT {
                    continue;
                }
                let declared_by: Vec<&str> = self
                    .expand_allocators(&suite.allocators)
                    .iter()
                    .filter_map(|id| self.spec(id))
                    .filter(|s| {
                        s.variants
                            .as_deref()
                            .is_some_and(|vs| vs.iter().any(|v| v == variant))
                    })
                    .map(|s| s.id.as_str())
                    .collect();
                if declared_by.is_empty() {
                    return Err(format!(
                        "suite {:?} asks for variant {:?}, which no allocator it names \
                         declares in allocators.toml -- a typo here would expand to \
                         nothing and measure the default instead, so it is an error",
                        suite.id, variant
                    ));
                }
            }
            for distro_raw in &suite.distros {
                for arch in &suite.arches {
                    let distro = effective_distro(distro_raw, arch);
                    let libc = libc_for(&distro).to_string();
                    for alloc_id in self.expand_allocators(&suite.allocators) {
                        let Some(spec) = self.spec(&alloc_id) else {
                            return Err(format!(
                                "suite {:?} names allocator {:?}, which is not in allocators.toml",
                                suite.id, alloc_id
                            ));
                        };
                        for integration_raw in &suite.integrations {
                            // The control has nothing to integrate; whatever a
                            // suite asks for, `system` is always `baseline`.
                            let integration = if spec.is_baseline() {
                                "baseline".to_string()
                            } else {
                                integration_raw.clone()
                            };
                            let profiles =
                                suite.profiles_by_arch.get(arch).unwrap_or(&suite.profiles);
                            // Which variants THIS allocator can be built in.
                            //  The intersection matters: a suite asking for
                            // `light` alongside the control must not produce a
                            // `system-light` control that no recipe could
                            // build and nothing could be compared against.
                            let variants = applicable_variants(spec, &suite.variants);
                            for profile in profiles {
                                for toolchain in &suite.toolchains {
                                    for variant in &variants {
                                        let id = Cell::slug_with_variant(
                                            &distro,
                                            arch,
                                            &alloc_id,
                                            &integration,
                                            profile,
                                            toolchain,
                                            variant,
                                        );
                                        if seen.contains_key(&id) {
                                            continue;
                                        }
                                        let (status, reason) = self.judge(
                                            spec,
                                            &integration,
                                            profile,
                                            &libc,
                                            &distro,
                                            arch,
                                        );
                                        seen.insert(
                                            id.clone(),
                                            Cell {
                                                id,
                                                suite: suite.id.clone(),
                                                distro: distro.clone(),
                                                arch: arch.clone(),
                                                libc: libc.clone(),
                                                allocator: alloc_id.clone(),
                                                integration: integration.clone(),
                                                profile: profile.clone(),
                                                toolchain: toolchain.clone(),
                                                corpus: suite.corpus.clone(),
                                                repeat: suite.repeat,
                                                variant: variant.clone(),
                                                status,
                                                reason,
                                            },
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(seen.into_values().collect())
    }

    /// Can this cell exist? A `no` carries the concrete technical reason,
    /// which is the deliverable for that row.
    fn judge(
        &self,
        spec: &AllocatorSpec,
        integration: &str,
        profile: &str,
        libc: &str,
        distro: &str,
        arch: &str,
    ) -> (String, Option<String>) {
        let no = |r: String| ("unsupported".to_string(), Some(r));

        //  static-PIE DOES NOT EXIST on aarch64 musl, and this is checked here
        // rather than discovered by the identity gate on every run.
        //
        // It is a property of rustc's target definition, not of this project's
        // flags and not of the linker. Measured, rustc 1.94.1, with
        // `RUSTC_BOOTSTRAP=1 rustc -Z unstable-options --print target-spec-json`:
        //
        //   x86_64-unknown-linux-musl   static-position-independent-executables: true
        //   aarch64-unknown-linux-musl  static-position-independent-executables: ABSENT
        //
        // so rustc emits `-static -no-pie` on the aarch64 link line and
        // `-static-pie` on the x86_64 one.  Both targets already use the SAME
        // linker flavour, `gnu-cc` -- the gcc driver -- so changing driver is
        // not the lever it was once thought to be.
        //
        //  THE ALTERNATIVE WAS TO RELAX THE IDENTITY ORACLE, and that is the
        // exact failure docs/AGENTS.md exists to prevent: the first aarch64
        // dispatch built six cells and the oracle rejected all six for wearing a
        // `static-pie-lto` label on a plain-static binary. The oracle is right.
        // A configuration that cannot exist is published as a row with its
        // reason (§15), which is what this does.
        if arch == "aarch64" && libc == "musl" && profile.starts_with("static-pie") {
            return no(format!(
                "static-PIE does not exist for `aarch64-unknown-linux-musl`. rustc's target definition                  leaves `static-position-independent-executables` unset there (it is true for                  x86_64-unknown-linux-musl), so rustc puts `-static -no-pie` on the link line and the                  result is a plain-static ELF that the identity gate correctly refuses to publish under                  a `{}` label. Both targets already use the `gnu-cc` linker flavour, so this is not a                  linker-driver choice. aarch64/musl is measured on the non-PIE `static` profiles instead;                  see docs/history/todo/platform.md T-002.",
                profile
            ));
        }

        if spec.is_baseline() {
            // The control exists everywhere except where the profile itself
            // cannot exist.
            if profile == "dynamic" && libc == "musl" && integration == "preload" {
                // Still fine: Alpine can build dynamic musl binaries.
            }
            return ("planned".to_string(), None);
        }

        if !spec.supports(integration) {
            return no(spec.why_not(integration));
        }

        // A static binary has no dynamic loader, so there is nothing to
        // interpose. This is a property of the profile, not of the allocator.
        if integration == "preload" && profile != "dynamic" {
            return no(format!(
                "LD_PRELOAD needs a dynamic loader to interpose, and the `{}` profile produces a binary with no PT_INTERP. \
                 Preload is measured on the `dynamic` profile only.",
                profile
            ));
        }

        // Replacing malloc inside a *static* glibc is the case that does not
        // work, and it is worth stating precisely rather than discovering it
        // as a link error every run.
        if libc == "glibc"
            && matches!(integration, "libc-surgery" | "link-override")
            && profile.starts_with("static")
        {
            return no(format!(
                "glibc's malloc object in libc.a also defines symbols the rest of glibc references internally \
                 (__libc_malloc and the arena hooks), so removing it breaks the archive and leaving it in place \
                 gives two definitions of malloc. Statically replacing glibc's allocator is therefore not \
                 supported on {}; the same allocator IS measured there through `rust-global`, and through \
                 `preload` on the dynamic profile.",
                distro
            ));
        }

        ("planned".to_string(), None)
    }
}
