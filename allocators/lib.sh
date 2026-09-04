# shellcheck shell=sh
# Shared helpers for the per-allocator build recipes.
#
# THE CONTRACT every allocators/<id>/build.sh honours
#
#   IN, as environment:
#     SRC          the allocator source tree, already at the pinned commit
#     OUT          install prefix to create; the archive goes in $OUT/lib
#     MODE         prefixed | override | preload
#                    prefixed -> exports mi_malloc / je_mallocx / sn_malloc ...
#                                and does NOT define malloc. Used by the
#                                rust-global mechanism.
#                    override -> defines malloc/free/realloc/... themselves.
#                                Used by libc-surgery and link-override.
#                    preload  -> the SAME symbol set as override, in a SHARED
#                                OBJECT rather than an archive. Used by the
#                                preload mechanism, which interposes at load
#                                time instead of at link time.
#     PIC          1 for a position-independent archive (required for
#                  static-PIE), 0 otherwise
#     LIBC         musl | glibc
#     TARGET_ARCH  x86_64 | aarch64
#     NPROC, CC, CXX, AR
#
#   OUT, on success:
#     $OUT/lib/liballocbench.a    the archive, under one name for every
#                                 allocator so the consumer never has to know
#                                 which one it linked
#     $OUT/lib/liballocbench.so   MODE=preload only, and under one name for the
#                                 same reason.  The name is FIXED: a consumer
#                                 that globs for it can be handed the wrong file.
#     $OUT/meta.env               ALLOC_LINK_CXX=... and the flags used
#
#   EXIT CODES
#     0  built
#     3  UNSUPPORTED in this configuration -- prints `UNSUPPORTED: <reason>`
#        on stdout.  This is a RESULT, not an error: the orchestrator records
#        the reason and the report prints the cell as unsupported rather than
#        dropping it. A configuration that silently disappears from a matrix is
#        indistinguishable from one nobody thought of.
#     other  the build was attempted and failed

set -eu

: "${SRC:?SRC is required}"
: "${OUT:?OUT is required}"
: "${MODE:=prefixed}"
: "${PIC:=1}"
: "${LIBC:=musl}"
: "${TARGET_ARCH:=x86_64}"
: "${NPROC:=$(nproc 2>/dev/null || echo 2)}"
: "${CC:=cc}"
: "${CXX:=c++}"
: "${AR:=ar}"

ARCHIVE="$OUT/lib/liballocbench.a"
SHARED="$OUT/lib/liballocbench.so"

unsupported() {
    printf 'UNSUPPORTED: %s\n' "$1"
    exit 3
}

prepare_out() {
    rm -rf "$OUT"
    mkdir -p "$OUT/lib" "$OUT/include"
}

finish() {
    # $@ = symbols that MUST be defined in the archive
    [ -f "$ARCHIVE" ] || { echo "build did not produce $ARCHIVE" >&2; exit 1; }

    if ! syms=$("$NM" --defined-only "$ARCHIVE" 2>&1); then
        echo "cannot read the symbol table of $ARCHIVE with '$NM'" >&2
        echo " This says NOTHING about the allocator: the archive was built and" >&2
        echo "   the tool that inspects it failed. $NM said:" >&2
        printf '%s\n' "$syms" | head -10 | sed 's/^/   | /' >&2
        exit 2   # could not run -- never reported as a pass. docs/AGENTS.md
    fi

    missing=''
    for sym in "$@"; do
        if ! printf '%s\n' "$syms" | grep -qE "[[:space:]][TtWwDdBb][[:space:]]+$sym\$"; then
            missing="$missing $sym"
        fi
    done
    if [ -n "$missing" ]; then
        echo "archive $ARCHIVE is missing required symbol(s):$missing" >&2
        n=$(printf '%s\n' "$syms" | grep -c '[^[:space:]]' || true)
        if [ "$n" -eq 0 ]; then
            echo " and it defines NOTHING AT ALL: 0 symbols in the archive." >&2
            echo "   An archive with an empty symbol table is a build result --" >&2
            echo "   no objects added, or every object empty -- not a missing API." >&2
        else
            echo "--- $n defined symbol(s); first 40 ---" >&2
            printf '%s\n' "$syms" | head -40 >&2
        fi
        exit 1
    fi

    if [ "$MODE" = prefixed ]; then
        if printf '%s\n' "$syms" | grep -qE '[[:space:]]T[[:space:]]+malloc$'; then
            echo "archive defines malloc in prefixed mode: the override layer was not disabled" >&2
            exit 1
        fi
    else
        if ! printf '%s\n' "$syms" | grep -qE '[[:space:]][TW][[:space:]]+malloc$'; then
            echo "archive does not define malloc in override mode: nothing would be replaced" >&2
            exit 1
        fi
    fi

    size=$(wc -c < "$ARCHIVE")
    echo "built $ARCHIVE ($size bytes, mode=$MODE pic=$PIC libc=$LIBC arch=$TARGET_ARCH)"
}

elf_kind() {
    [ -f "$1" ] && [ -r "$1" ] || { echo "not-readable"; return; }
    _magic=$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')
    [ "$_magic" = "7f454c46" ] || { echo "not-elf"; return; }
    # e_type, 2 bytes at offset 16. Accepted in either byte order rather than
    # parsing EI_DATA: this project targets x86_64 and aarch64, both little
    # endian, and matching both spellings costs nothing and cannot be wrong.
    _etype=$(od -An -tx1 -j16 -N2 "$1" 2>/dev/null | tr -d ' \n')
    case "$_etype" in
        0100|0001) echo "elf-relocatable" ;;   # ET_REL: a .o wearing a .so name
        0200|0002) echo "elf-executable" ;;    # ET_EXEC
        0300|0003) echo "elf-shared" ;;        # ET_DYN, the one we want
        *)         echo "elf-other-$_etype" ;;
    esac
}

ar_kind() {
    [ -f "$1" ] && [ -r "$1" ] || { echo "not-readable"; return; }
    _magic=$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')
    if [ "$_magic" = "213c617263683e0a" ]; then echo "ar-archive"; else echo "not-an-archive"; fi
}

_pick_by_kind() {   # $1 = classifier function, $2 = the kind that wins
    _found=''
    _report=''
    _seen=''
    while IFS= read -r _cand; do
        [ -n "$_cand" ] || continue
        case "$_seen" in
            *"|$_cand|"*) continue ;;
        esac
        _seen="$_seen|$_cand|"
        _kind=$("$1" "$_cand")
        if [ -z "$_found" ] && [ "$_kind" = "$2" ]; then
            _found="$_cand"
        else
            _report="$_report
  $_kind  $_cand"
        fi
    done
    if [ -n "$_found" ]; then
        [ -z "$_report" ] || printf 'note: not taken (first %s wins):%s\n' "$2" "$_report" >&2
        printf '%s\n' "$_found"
        return 0
    fi
    [ -z "$_report" ] || printf 'no candidate is %s:%s\n' "$2" "$_report" >&2
    return 1
}

pick_ar() { _pick_by_kind ar_kind ar-archive; }

pick_elf_so() { _pick_by_kind elf_kind elf-shared; }

finish_so() {
    # $@ = symbols that MUST be exported by the shared object
    [ -f "$SHARED" ] || { echo "build did not produce $SHARED" >&2; exit 1; }

    if ! dynsyms=$("$NM" -D --defined-only "$SHARED" 2>&1); then
        echo "cannot read the dynamic symbol table of $SHARED with '$NM'" >&2
        echo " This says NOTHING about the allocator: the library was built and" >&2
        echo "   the tool that inspects it failed. $NM said:" >&2
        printf '%s\n' "$dynsyms" | head -10 | sed 's/^/   | /' >&2
        exit 2   # could not run -- never reported as a pass. docs/AGENTS.md
    fi

    missing=''
    for sym in "$@"; do
        if ! printf '%s\n' "$dynsyms" | grep -qE "[[:space:]][TtWwDdBbIi][[:space:]]+$sym\$"; then
            missing="$missing $sym"
        fi
    done
    if [ -n "$missing" ]; then
        echo "shared object $SHARED does not EXPORT required symbol(s):$missing" >&2
        n=$(printf '%s\n' "$dynsyms" | grep -c '[^[:space:]]' || true)
        if [ "$n" -eq 0 ]; then
            echo " and it exports NOTHING AT ALL: 0 defined dynamic symbols." >&2
            echo "   That is a property of how it was LINKED, not of the allocator:" >&2
            echo "   a shared object built with no exported-symbols list, or whose" >&2
            echo "   objects were all localised, has an empty .dynsym." >&2
        else
            echo "--- $n defined dynamic symbol(s); first 40 ---" >&2
            printf '%s\n' "$dynsyms" | head -40 >&2
        fi
        exit 1
    fi

    if ! printf '%s\n' "$dynsyms" | grep -qE '[[:space:]][TWi][[:space:]]+malloc$'; then
        echo "shared object does not export malloc: LD_PRELOAD would interpose nothing" >&2
        exit 1
    fi

    size=$(wc -c < "$SHARED")
    echo "built $SHARED ($size bytes, mode=$MODE pic=$PIC libc=$LIBC arch=$TARGET_ARCH)"
}

# `nm` is not in Alpine's base image and the LTO-aware variants differ by
# compiler. Resolved once, here, so every recipe agrees.
NM="${NM:-}"
if [ -z "$NM" ]; then
    for c in llvm-nm gcc-nm nm; do
        if command -v "$c" >/dev/null 2>&1; then NM="$c"; break; fi
    done
fi
: "${NM:?no nm found; install binutils or llvm}"

fortify_cflags() { printf -- '-U_FORTIFY_SOURCE'; }

pic_cflags() {
    if [ "$PIC" = 1 ]; then printf -- '-fPIC'; else printf -- '-fno-PIC -fno-PIE'; fi
}

# The link half of the same thing. `-fno-PIE` tells the COMPILER; the driver
# still passes `-pie` to the linker unless told otherwise, and a recipe that
# links anything -- including a configure or cmake feature test -- needs both.
pic_ldflags() {
    if [ "$PIC" = 1 ]; then printf -- ''; else printf -- '-no-pie'; fi
}

write_meta() {
    {
        printf "ALLOC_LINK_CXX='%s'\n" "$1"
        printf "ALLOC_LINK_SEARCH='%s'\n" "${ALLOC_LINK_SEARCH:-}"
        printf "ALLOC_MODE='%s'\n" "$MODE"
        printf "ALLOC_PIC='%s'\n" "$PIC"
        printf "ALLOC_LIBC='%s'\n" "$LIBC"
        printf "ALLOC_ARCH='%s'\n" "$TARGET_ARCH"
    } > "$OUT/meta.env"
    printf '%s\n' "$2" > "$OUT/build-flags.txt"
}
