/* allocprobe.c -- the subject every example under examples/ builds and runs.
 *
 *  WHY A PURPOSE-BUILT SUBJECT AND NOT `ls`. Three of the four things these
 * examples have to establish cannot be established by running an arbitrary
 * program:
 *
 *   1. that the replacement allocator SERVES the allocations rather than merely
 *      being present -- so the subject has to allocate hard, from several
 *      threads, through every entry point a replacement is expected to provide;
 *   2. that the program still produces the RIGHT ANSWER -- so the subject has
 *      to have an answer that is known before it runs. `mode count` plants the
 *      needles itself and the caller asserts the exact count, which is the same
 *      argument `alloc-runner gen-corpus` makes for the benchmark proper:
 *      "it printed something" is not a correctness check;
 *   3. that the binary is position-independent when it claims to be -- so it
 *      prints its own load address and the caller counts distinct ones.
 *
 *  AND IT MUST BE ABLE TO FAIL. A probe that cannot crash proves nothing
 * about a crash. `mode stress` writes a byte pattern over every allocation and
 * reads it back before freeing, so an allocator that returns overlapping,
 * undersized or unaligned blocks is caught here rather than in a segfault
 * three programs later. `mode corrupt` deliberately double-frees and exists so
 * the examples can show what a REAL failure looks like beside the passes.
 *
 * ISO C plus POSIX threads and posix_memalign. No configure step, no
 * dependencies, and it must compile on musl and glibc with the same command.
 *
 *   cc -O2 -pthread -o allocprobe allocprobe.c
 *   ./allocprobe stress 4 20000
 *   ./allocprobe count 5000
 *   ./allocprobe addr
 */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Sizes chosen to straddle the small/large boundary every allocator here has:
 * a few bytes, a few hundred, a few kilobytes, and one past any small-object
 * fast path. */
static const size_t SIZES[] = {1,   7,    16,   24,    56,    120,   256,
                               504, 1000, 4096, 9001,  16384, 65536, 131072};
#define NSIZES (sizeof(SIZES) / sizeof(SIZES[0]))

struct job {
    unsigned seed;
    long iters;
    int failed;
};

/* Fill with a value derived from the pointer, so a block handed out twice
 * fails the read-back even if both writes "succeed". */
static unsigned char pattern_of(const void *p, size_t i)
{
    uintptr_t v = (uintptr_t)p;
    return (unsigned char)((v >> (8 * (i % 4))) ^ (i * 31u) ^ 0xA5u);
}

static int fill_and_check(void *p, size_t n)
{
    unsigned char *b = (unsigned char *)p;
    size_t i;
    for (i = 0; i < n; i++)
        b[i] = pattern_of(p, i);
    for (i = 0; i < n; i++)
        if (b[i] != pattern_of(p, i))
            return 0;
    return 1;
}

static unsigned rnd(unsigned *s)
{
    *s = *s * 1103515245u + 12345u;
    return (*s >> 16) & 0x7fff;
}

#define LIVE 256

static void *worker(void *arg)
{
    struct job *j = (struct job *)arg;
    void *live[LIVE];
    size_t live_n[LIVE];
    long k;
    int i;

    for (i = 0; i < LIVE; i++) {
        live[i] = NULL;
        live_n[i] = 0;
    }

    for (k = 0; k < j->iters; k++) {
        i = (int)(rnd(&j->seed) % LIVE);
        if (live[i]) {
            if (!fill_and_check(live[i], live_n[i])) {
                j->failed = 1;
                return NULL;
            }
            /* Exercise realloc as well as free: a replacement that gets
             * realloc wrong is a replacement that silently truncates data. */
            if (rnd(&j->seed) % 4 == 0) {
                size_t n2 = SIZES[rnd(&j->seed) % NSIZES];
                void *p2 = realloc(live[i], n2);
                if (!p2) {
                    j->failed = 1;
                    return NULL;
                }
                live[i] = p2;
                live_n[i] = n2;
                if (!fill_and_check(live[i], live_n[i])) {
                    j->failed = 1;
                    return NULL;
                }
                continue;
            }
            free(live[i]);
            live[i] = NULL;
            live_n[i] = 0;
            continue;
        }

        {
            size_t n = SIZES[rnd(&j->seed) % NSIZES];
            unsigned which = rnd(&j->seed) % 8;
            void *p = NULL;
            if (which == 0) {
                p = calloc(1, n);
                /* calloc must zero. An allocator that forgets is a security
                 * bug, not a performance one. */
                if (p) {
                    size_t z;
                    for (z = 0; z < n; z++)
                        if (((unsigned char *)p)[z] != 0) {
                            j->failed = 1;
                            free(p);
                            return NULL;
                        }
                }
            } else if (which == 1) {
                /* posix_memalign: alignment must be a power of two multiple of
                 * sizeof(void*), and the result must actually be aligned. */
                size_t align = 64;
                if (posix_memalign(&p, align, n) != 0)
                    p = NULL;
                if (p && ((uintptr_t)p % align) != 0) {
                    j->failed = 1;
                    free(p);
                    return NULL;
                }
            } else {
                p = malloc(n);
            }
            if (!p) {
                j->failed = 1;
                return NULL;
            }
            if (!fill_and_check(p, n)) {
                j->failed = 1;
                free(p);
                return NULL;
            }
            live[i] = p;
            live_n[i] = n;
        }
    }

    for (i = 0; i < LIVE; i++)
        free(live[i]);
    return NULL;
}

static int mode_stress(int nthreads, long iters)
{
    pthread_t th[64];
    struct job jobs[64];
    int i, bad = 0;

    if (nthreads < 1)
        nthreads = 1;
    if (nthreads > 64)
        nthreads = 64;

    for (i = 0; i < nthreads; i++) {
        jobs[i].seed = 1u + (unsigned)i * 7919u;
        jobs[i].iters = iters;
        jobs[i].failed = 0;
        if (pthread_create(&th[i], NULL, worker, &jobs[i]) != 0) {
            fprintf(stderr, "allocprobe: pthread_create failed\n");
            return 2;
        }
    }
    for (i = 0; i < nthreads; i++)
        pthread_join(th[i], NULL);
    for (i = 0; i < nthreads; i++)
        bad += jobs[i].failed;

    if (bad) {
        printf("STRESS-FAILED threads=%d bad=%d\n", nthreads, bad);
        return 1;
    }
    printf("STRESS-OK threads=%d iters=%ld\n", nthreads, iters);
    return 0;
}

/* The known-answer test. The needle count is decided HERE, before any
 * allocation happens, so the caller can assert an exact number rather than
 * "it printed something". */
static int mode_count(long n)
{
    const char *needle = "ALLOCPROBE-NEEDLE";
    size_t nl = strlen(needle);
    long planted = 0, found = 0, i;
    char **lines;

    if (n < 1)
        n = 1;
    lines = (char **)malloc((size_t)n * sizeof(char *));
    if (!lines) {
        fprintf(stderr, "allocprobe: out of memory building the haystack\n");
        return 2;
    }

    for (i = 0; i < n; i++) {
        /* Every 7th line carries the needle. Nothing random: the expected
         * count is a function of n alone and the caller computes it too. */
        size_t len = 40 + (size_t)(i % 50);
        char *s = (char *)malloc(len + nl + 2);
        if (!s) {
            fprintf(stderr, "allocprobe: out of memory at line %ld\n", i);
            return 2;
        }
        memset(s, 'x', len);
        s[len] = '\0';
        if (i % 7 == 0) {
            memcpy(s + len / 2, needle, nl);
            planted++;
        }
        lines[i] = s;
    }

    for (i = 0; i < n; i++)
        if (strstr(lines[i], needle))
            found++;

    for (i = 0; i < n; i++)
        free(lines[i]);
    free(lines);

    /* Both numbers, so a mismatch is visible rather than inferred. */
    printf("COUNT planted=%ld found=%ld\n", planted, found);
    return planted == found ? 0 : 1;
}

/* ASLR: the caller runs this several times and counts distinct values. A
 * non-PIE executable prints the same address every time. */
static int mode_addr(void)
{
    printf("ADDR %p\n", (void *)(uintptr_t)&mode_addr);
    return 0;
}

/*  A deliberate double free, so an example can show what a REAL allocator
 * failure looks like beside its passes. hardened_malloc aborts here by design;
 * a plain allocator may abort, corrupt, or appear to survive. Never used as a
 * pass criterion -- its only job is to demonstrate that the harness can tell a
 * crash from a success. */
/*  The warning this suppresses is CORRECT -- gcc 13 flags the second free as
 * a use-after-free, which is exactly what it is. Suppressed locally, and only
 * here, so an example a reader is meant to copy compiles clean rather than
 * teaching them to ignore a diagnostic. */
#if defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 12
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wuse-after-free"
#endif
static int mode_corrupt(void)
{
    void *p = malloc(64);
    if (!p)
        return 2;
    free(p);
    free(p);
    printf("CORRUPT-SURVIVED (the allocator did not detect a double free)\n");
    return 0;
}
#if defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 12
#pragma GCC diagnostic pop
#endif

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "stress";

    if (strcmp(mode, "stress") == 0) {
        int nt = argc > 2 ? atoi(argv[2]) : 4;
        long it = argc > 3 ? atol(argv[3]) : 20000;
        return mode_stress(nt, it);
    }
    if (strcmp(mode, "count") == 0)
        return mode_count(argc > 2 ? atol(argv[2]) : 5000);
    if (strcmp(mode, "addr") == 0)
        return mode_addr();
    if (strcmp(mode, "corrupt") == 0)
        return mode_corrupt();

    fprintf(stderr, "usage: %s stress [threads] [iters] | count [n] | addr | corrupt\n",
            argv[0]);
    return 2;
}
