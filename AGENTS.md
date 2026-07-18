# Agent Notes — Offline ArchISO

## Session preamble
```
We're working on offline archiso project. Currently having baseline profile ready and building. Do not guess anything. Do not auto-commit after changes. Commit only after my approval. Before we begin read OVERVIEW.md
```

## Build requires root
Cannot build from this environment — `build.sh` uses `sudo` internally.
User must run builds manually:

```bash
./build.sh    # Build the ISO (requires root)
./run.sh      # Test in QEMU (requires KVM)
```