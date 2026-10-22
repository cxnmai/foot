# Fork performance work

## Build

The fork now defaults to `buildtype=release`. Existing build directories retain
old options: explicitly reconfigure them or use a fresh directory. The locally
installed binary used for the original benchmark was an `-O0` debug build.
Zig remains safety-checked (`-O safe`); the gains do not require disabling its
bounds checks.

```sh
meson setup bld/perf --buildtype=release -Db_lto=true
meson compile -C bld/perf
meson test -C bld/perf --print-errorlogs
```

## Changes

- Batch ordinary printable ASCII within a row; preserve scalar handling for
  wrapping, insert mode, charsets, metadata, and non-ASCII/control bytes.
- Batch Kitty APC payload bytes across the C/Zig boundary.
- Replace named graphics placements instead of accumulating duplicates; honor
  placement IDs on deletion and keep images referenced by other placements.
- Coalesce graphics text invalidation until the next rendered frame.
- Paint small dirty grids serially instead of waking every render worker.
- Release hidden tabs' disposable grid framebuffers after preapply completes;
  compositor-busy buffers retain deferred destruction. Terminal contents remain.

## Isolated measurements

Medians of three fresh-process trials per binary, using the workloads from
`../term-benchmarks/workload.py`. Weston 15.0.1 headless/Pixman, private runtime
and Wayland socket, software rendering, 1920x1080 output at 60 Hz, 133x40 grid,
JetBrains Mono 11, empty configuration, SCHED_OTHER/nice 0. No desktop focus or
input injection. CPU excludes producer and compositor. All graphics probes pass.

| Measurement | Installed debug baseline | Release baseline | Final release |
|---|---:|---:|---:|
| ASCII MiB/s | 21.4 | 105.0 | 224.7 |
| ANSI MiB/s | 26.0 | 106.5 | 160.6 |
| Unicode MiB/s | 23.1 | 89.8 | 94.8 |
| 10,000 redraw updates, seconds | 1.195 | 0.322 | 0.166 |
| Paced 60 Hz updates, CPU-seconds / 4 s | 2.09 | 1.54 | 0.76 |
| 30 graphics uploads, seconds | 0.927 | 0.627 | 0.543 |
| 10,000 cached placements, seconds | 3.202 | 0.383 | 0.022 |
| Median parser round-trip, microseconds | 21.5 | 18.4 | 18.3 |

These are parser fences, not displayed FPS. Do not compare these absolute values
with the original live niri/blur results or infer cross-terminal rankings.
Placement baselines also had incorrect replacement semantics; the new engine
regression test verifies 10,000 replacements retain one record per named ID.
The release baseline includes the hidden-tab cache fix (irrelevant to these
single-tab tests). Native-tab memory savings have not been remeasured.

Local raw results: `/tmp/foot-headless-{debug-before,release-before,final-after}.jsonl`.
The scratch isolated runner and setup notes are in `/tmp/foot-headless.iKYsnu/`;
Weston was extracted privately, not installed system-wide. The runner does not
use the live-desktop `Session` harness. Scratch artifacts are not permanent.

Validation: all ten integrated Meson suites pass, including ASCII differential
coverage, APC control/split/overflow tests, and graphics engine replacement and
delete tests. Independent source reviews found no runtime correctness issues.
