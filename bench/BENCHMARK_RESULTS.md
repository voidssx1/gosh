# GOSH Benchmark Results

**Execution Date**: 2026-11-07 19:13:16 UTC
**Platform**: Linux (x86_64, 6.18.56)

### Evaluated Shells
- **gosh**: `/home/aditya/gosh/bin/gosh`
- **bash**: `/run/current-system/sw/bin/bash`
- **zsh**: `/home/aditya/.nix-profile/bin/zsh`
- **sh**: `/run/current-system/sw/bin/sh`

### Results Summary (lower is better, in milliseconds)

Each workload is validated before timing. Any failed check, nonzero exit, launch error, or timeout invalidates the whole cell; partial timings are discarded.
Per-process timeout: 10 s. Validation runs are excluded from timings; LC_ALL=C.

| Benchmark | Description | Unit | gosh | bash | zsh | sh |
|:---|:---|:---|---:|---:|---:|---:|
| **Shell Startup & Exit (50 runs)** | Measures cold process spawn and shell initialization overhead | ms total | 68.31 | 66.00 | 130.51 | 67.49 |
| **Arithmetic Loop (1,000 iterations)** | Evaluates while loop, conditional test, and $((i + 1)) arithmetic evaluation | ms/run (mean) | 2.62 | 3.85 | 5.41 | 3.78 |
| **Pipeline Throughput (30 runs)** | 3-stage pipeline (printf \| sort \| head) measuring fork, pipe, and IPC coordination | ms total | 101.07 | 103.24 | 169.39 | 100.72 |
| **Command Substitution (30 runs)** | Subshell output capture: echo $(echo benchmark_value) | ms total | 56.47 | 51.19 | 88.92 | 52.70 |
| **Function Call Overhead (200 calls)** | Function invocation with arguments and redirection | ms/run (mean) | 4.34 | 4.05 | 6.97 | 4.11 |
