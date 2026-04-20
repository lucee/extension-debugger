# Repro — JDWP class-load hang

Frozen snapshot of the BDD test pattern that triggered the 20–30 s hang
at `Class.getDeclaredConstructors0` documented in the runtime notes.
Preserved deliberately so the pathological concurrency pattern is still
runnable after the normal test harness gets the `waitForHttpComplete`
pacing fix.

Not part of CI. Label-gated so the default `testLabels=dap` runner
skips it.

## Background

Three layers of the same bug, spelled out in
[classload-hang-summary.md](../../../../../../lucee-projects/runtime/classload-hang-summary.md):

1. **JDK layer** (JDK-8227269) — `classTrack_processUnloads` iterates
   all loaded classes on GC, O(classCount²) under class-load bursts.
   Fixed in JDK 11.0.9 but residual cost remains on JDK 21.
2. **Lucee layer** — `PageSourceImpl.loadPhysical` holds
   `synchronized(this)` across `defineClass`, which runs every
   `ClassFileTransformer` and delivers `ClassPrepareEvent` while the
   monitor is held. Waiter threads 2..N pile up.
3. **Debugger extension layer** — `ClassPrepareEvent` handler does
   JDWP round-trips (`KlassMap.maybeNull_tryBuildKlassMap`) before
   returning.

This test triggers all three simultaneously by firing 5+ concurrent
fire-and-forget `triggerArtifact` calls against the same unloaded
`$cf` class.

See also
[bdd-vs-xunit-debuggee-slowdown.md](../../../../../lucee-projects/extensions/debugger/bdd-vs-xunit-debuggee-slowdown.md)
for the full investigation story.

## How to run

From `test/cfml/`:

```bash
set testLabels=reproOnly
test.bat
```

The default `testLabels=dap` in `test.bat` skips this folder. Override
via env var as above.

## What "reproduces" means

Expected symptoms on Lucee 6.2 or 7.1 **agent mode** + JDK 21 + attached
debugger:

- `triggerArtifact` HTTP errors with `elapsedMs=10000` (hits the 10 s
  HTTP client timeout) on `variables-target`, `null-target`,
  `stepping-target` — the files loaded concurrently by the early BDD
  lifecycle
- Multiple `it` blocks fail with "HTTP error 408" or "waitForEvent
  timed out"
- Full suite wall-clock 120–170 s vs. ~20 s baseline

Does **not** reproduce on:

- Lucee 7.1 **native** mode (no JDWP attached)
- JDWP attached but no debugger breakpoints set
- Single-threaded / serialised test harness

## What's in this folder

Snapshot of the four files needed to reproduce; artifacts are shared
with the parent `test/cfml/artifacts/` tree via a relative path tweak
in the local `DapTestCase.cfm`:

- `TemplateIncludeTest.cfc` — the pathological BDD spec
  (`labels="reproOnly"`)
- `DapTestCase.cfm` — harness (local copy; `getArtifactPath` points up
  two levels)
- `DapTestCase.cfc` — base class
- `DapClient.cfc` — DAP protocol client

## Maintenance

Intentionally frozen. If the main harness changes significantly
(new helper functions, new DAP-protocol capabilities) this repro may
need a manual refresh to keep running — but the point of the folder is
to preserve the concurrency pattern that reproduced the bug, not to
track harness evolution. If it stops reproducing because the main
harness added a pacing fix to `afterEach`, that's fine — just keep the
local copy here unchanged so the repro still works.

## Related

- Testbed with JFR recording:
  `D:/testbeds/extension-debugger-bdd-jfr/`
- Lucee-side investigation:
  [jdwp-getDeclaredConstructors0-hang.md](../../../../../../lucee-projects/runtime/jdwp-getDeclaredConstructors0-hang.md)
- Debugger-extension-side design:
  `../../../../../lucee-projects/extensions/debugger/classprepare-hold-fix-design.md`
