# luceedebug Profiling

This directory contains tools for profiling luceedebug performance using Java Flight Recorder (JFR).

## Findings Summary (2025-12-03)

### Performance Overhead

Benchmark results with 100,000 iterations on Lucee 7.1.0.7-ALPHA:

| Benchmark | Baseline | With Agent | Overhead |
|-----------|----------|------------|----------|
| Simple function calls | 111ms | 175ms | **+58%** |
| Multi-line function | 99ms | 155ms | **+57%** |
| Nested function calls | 132ms | 236ms | **+79%** |
| Recursive calls (depth=10) | 373ms | 540ms | **+45%** |
| Mixed workload | 323ms | 593ms | **+84%** |

**Key observation:** ~50-80% overhead with agent loaded but NOT actively debugging.

### Real-World Test: lucee-spreadsheet

| Test | Baseline | With Agent | Overhead |
|------|----------|------------|----------|
| Spreadsheet test suite | 20s | 25s | **+25%** |

The real-world overhead is lower (~25%) because:

- Synthetic benchmarks hammer function calls exclusively
- Real code spends time in I/O, Java libraries, etc. (not instrumented)
- Class loading overhead is amortised over more work

### Hot Methods (from JFR)

**Synthetic benchmark** - most frequently sampled luceedebug methods:

1. `luceedebug_stepNotificationEntry_step` - Called on every CFML line
2. `getTopmostFrame` - Called from step notification
3. `maybeUpdateTopmostFrame` - Called from step notification
4. `maybe_pushCfFrame_worker` - Called on function entry
5. `pushCfFrame` - Called on function entry
6. `popCfFrame` - Called on function exit

**Real-world (lucee-spreadsheet)** - different profile:

1. **ASM ClassReader** (75+ samples) - bytecode transformation at class load
2. **udfCall wrappers** (108 samples) - function call wrappers
3. **pushCfFrame/popCfFrame** (31 samples) - frame management
4. **step notification** (5 samples) - much lower than synthetic

In real apps, class loading overhead dominates initially, then function wrappers.

### JFR Detailed Analysis (lucee-spreadsheet)

| Metric | Baseline | With Agent | Difference |
|--------|----------|------------|------------|
| Duration | 20s | 25s | +5s (+25%) |
| ExecutionSamples | 392 | 526 | +134 |
| ClassLoad events | 10,784 | 11,227 | +443 extra classes |
| TLAB allocations | 3,050 | 7,457 | **+4,407 (+144%)** |
| GC pauses | 47 | 75 | +28 (+60%) |
| GC count | 42 | 64 | +22 (+52%) |

**luceedebug-specific allocations** (not present in baseline):

- 167× `Frame` - one per CFML function call
- 165× `Frame$FrameContext` - accompanies each Frame
- 360× `Long` (boxing from hash lookups)
- 350× `ArrayList$Itr` (iterator allocations)
- 120× `ConcurrentHashMap$Node` (hash map operations)

**JDWP overhead** (from having debug port open):

- 151× `ClassLoaderReference$VisibleClasses$ClassInfo`
- 106× `EventSetImpl`
- 104× `ClassTypeImpl`
- 74× `ClassPrepare` events

**Lock contention**: No luceedebug-related lock contention detected. All `JavaMonitorEnter` events were in `SecureRandom` (unrelated to luceedebug).

**Key insight**: Memory pressure is significant - 144% more TLAB allocations leads to 52% more GC cycles. Frame/FrameContext allocations per function call are a prime optimisation target.

### JIT Inlining Analysis

From `jdk.CompilerInlining` events, checking which hot methods get inlined:

| Method | Call site | Inlined? | Reason |
|--------|-----------|----------|--------|
| `Thread.currentThread()` | maybe_pushCfFrame_worker | ✅ Yes | intrinsic |
| `ConcurrentMap.get()` | maybe_pushCfFrame_worker | ❌ No | "no static binding" (interface call) |
| `ArrayList.size()` | maybe_pushCfFrame_worker | ✅ Yes | inline |
| `Thread.currentThread()` | stepNotificationEntry_step | ✅ Yes | intrinsic |
| `ConcurrentHashMap.get()` | stepNotificationEntry_step | ❌ No | "no static binding" |

**Key insight**: The `ConcurrentMap.get()` calls cannot be inlined because they're interface method calls. This happens on every function entry (`maybe_pushCfFrame_worker`) and every line (`stepNotificationEntry_step`). Using `ThreadLocal` instead of `ConcurrentHashMap` lookups for frame stacks would allow better JIT optimisation.

### Stack Overflow Issue

**IMPORTANT:** luceedebug can cause StackOverflowError on complex codebases.

The instrumentation wraps every function call:

```
original: udfCall() -> actual code
with luceedebug: udfCall() -> udfCall__luceedebug__udfCall() -> actual code
```

This doubles stack frame usage. The lucee-docs build with Pygments syntax highlighting hits the recursion limit and fails with StackOverflowError when luceedebug is attached.

**Workaround:** Increase stack size with `-Xss2m` or similar.

### Optimization Priorities

Based on profiling, the highest-impact optimizations would be:

1. **Fast-path for step notification** - Add `stepRequestByThread.isEmpty()` check to exit early when not stepping
2. **Pre-sized collections** - ArrayList for frame stacks, HashMap for line maps
3. **ThreadLocal stepping flag** - Avoid hash lookups entirely when not stepping

See `PERFORMANCE_PLAN.md` in project root for detailed optimization plan.

---

## Overview

luceedebug instruments every CFML function call and line execution. To understand the overhead, we need to profile:

1. **Baseline** - Lucee running WITHOUT luceedebug
2. **Attached** - Lucee running WITH luceedebug (debugger not connected)
3. **Connected** - Lucee running WITH luceedebug AND debugger connected
4. **Stepping** - Lucee running WITH active step-through debugging

## Files

- `benchmark.cfm` - CFML script that stresses the hot paths (function calls, line stepping)
- `profile-baseline.bat` - Run benchmark without luceedebug (baseline)
- `profile-with-agent.bat` - Run benchmark with luceedebug agent loaded
- `profile-baseline-docs.bat` - Run lucee-docs build without luceedebug
- `profile-with-agent-docs.bat` - Run lucee-docs build with luceedebug (may fail with StackOverflow)
- `profile-baseline-spreadsheet.bat` - Run lucee-spreadsheet tests without luceedebug
- `profile-with-agent-spreadsheet.bat` - Run lucee-spreadsheet tests with luceedebug
- `compare-results.bat` - Compare baseline vs with-agent results

## Prerequisites

1. Build luceedebug:

   ```cmd
   cd d:\work\lucee-extensions\luceedebug\luceedebug
   gradlew shadowJar
   ```

2. Ensure script-runner is available at `D:\work\script-runner`

3. (Optional) For docs build tests, ensure lucee-docs is at `D:\work\lucee-docs`

## Running the Profiles

### 1. Baseline (No luceedebug)

```cmd
profile-baseline.bat
```

This runs the benchmark with just Lucee, no debugger. Establishes the baseline performance.

### 2. With luceedebug Agent

```cmd
profile-with-agent.bat
```

This runs with luceedebug loaded but no debugger connected. Shows the passive overhead of having the agent attached.

### 3. Compare Results

```cmd
compare-results.bat
```

Shows side-by-side timing comparison.

## Analysing JFR Results

Open the `.jfr` files in JDK Mission Control (JMC) or use command line:

```cmd
rem Summary
jfr summary output\with-agent.jfr

rem Hot methods
jfr print --events jdk.ExecutionSample output\with-agent.jfr

rem Count luceedebug methods in samples
jfr print --events jdk.ExecutionSample output\with-agent.jfr | grep -oE "luceedebug[^)]*" | sort | uniq -c | sort -rn

rem Convert to JSON for scripting
jfr print --json output\with-agent.jfr > with-agent.json
```

### Key Things to Look For

1. **CPU Hotspots** - Which methods consume the most CPU?
   - Look for `luceedebug.*` methods in the flame graph
   - Compare time spent in `pushCfFrame`/`popCfFrame` vs actual CFML execution

2. **Lock Contention** - Are there synchronization bottlenecks?
   - Check `jdk.JavaMonitorEnter` events
   - Look for `ValTracker`, `DebugManager` lock waits

3. **Allocations** - Memory pressure from debugging?
   - Check `jdk.ObjectAllocationInNewTLAB` and `jdk.ObjectAllocationOutsideTLAB`
   - Look for `Optional`, `WeakReference`, `ArrayList` allocations in hot paths

4. **GC Impact** - Is the debugger causing more GC?
   - Compare GC pause times and frequency between baseline and with-agent runs

## Notes

- The benchmark uses `systemOutput()` not `writeOutput()` for script-runner compatibility
- ITERATIONS can be adjusted in `benchmark.cfm` for longer/shorter runs
- For stepping overhead analysis, you'd need to manually step through with VS Code
- Real-world workloads (like lucee-docs) may hit stack limits due to doubled frame usage
