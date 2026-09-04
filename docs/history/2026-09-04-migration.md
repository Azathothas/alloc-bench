# 2026-09-04 repository migration

The project moved into a fresh repository with one initial commit.

- The 428-file research corpus under `references/` was removed after confirming
  that build, test, benchmark, validation, and reporting paths did not read it.
- All 28 TODO entries were confirmed complete and retained under
  `docs/history/todo/`.
- Existing history moved to `docs/history/`.
- Current documentation was rewritten around one owner per subject. Historical
  reviews and completed-work records remain evidence, not instructions.
- Repository URLs, image names, in-container paths, and environment variable
  prefixes were normalized to `alloc-bench` throughout retained text and data.
- The 18 source commit IDs embedded in imported datasets are listed in
  `results/imported-commits.txt`; future datasets must name commits reachable
  from this repository.
- The project license changed to 0BSD for the new repository. Third-party
  allocator sources keep their upstream licenses.
