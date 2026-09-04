# Forbidden patterns

| Pattern | Use instead |
| --- | --- |
| unverified performance or portability claim | measured scope and evidence |
| missing measurement represented as zero | null or an explicit failed state |
| ranking an emulated run | record it and exclude it from ranking |
| comparing static and dynamic binaries | separate comparison groups |
| hard-coded allocator identity | symbol and mapping verification |
| silent fallback to the system allocator | fail the cell |
| hand-edited generated report | rerun its generator |
| current instructions in `docs/history/` | update the owning current guide |
| historical narrative in current docs | archive it under `docs/history/` |
| copied facts across guides | one owner plus links |
| emojis, marketing claims, or theatrical warnings | plain technical language |
| tool attribution in commits or docs | configured author identity only |
