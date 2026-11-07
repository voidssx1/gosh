# GOSH Benchmark Results

**Execution Date**: 2026-11-07 18:48:04 UTC
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
| **Shell Startup & Exit (50 runs)** | Measures cold process spawn and shell initialization overhead | ms total | 84.35 | 73.80 | 149.19 | 71.29 |
| **Arithmetic Loop (1,000 iterations)** | Evaluates while loop, conditional test, and $((i + 1)) arithmetic evaluation | ms/run (mean) | 2.64 | 4.09 | 6.23 | 4.01 |
| **Pipeline Throughput (30 runs)** | 3-stage pipeline (printf \| sort \| head) measuring fork, pipe, and IPC coordination | ms total | 117.10 | 122.35 | 172.21 | 116.80 |
| **Command Substitution (30 runs)** | Subshell output capture: echo $(echo benchmark_value) | ms total | 65.94 | 55.55 | 110.96 | 57.22 |
| **Function Call Overhead (200 calls)** | Function invocation with arguments and redirection | ms/run (mean) | 4.81 | 4.59 | 7.69 | 4.46 |
