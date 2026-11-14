# Performance

Budgets from the design (#5): below 0.5% of one core averaged at idle, below 50 MiB after warm-up, no sustained growth over eight hours.

## Measured 2026-11-14

MacBook Air M3 (Mac15,13), macOS 27.2, ad-hoc arm64 build at 2c2ce4c, user's saved layout, 1 s sampling.

| Scenario | CPU (one core) | Footprint |
| --- | --- | --- |
| Idle, panel never opened (2 min) | 0.36% | 12 MB |
| Panel open (1 min) | ~1% | 24–28 MB |
| Idle after panel was opened and closed (2 min) | 0.33% | 24 MB |
| One-hour soak after one open/close | 0.42% average | 26–27 MB, flat for the last 50 min |

App bundle: 5.7 MB (arm64). Footprint is what Activity Monitor's Memory column shows; RSS (65–95 MB) also counts shared system framework pages and is not the budget metric. Freed panel memory is not returned to the OS immediately, so footprint stays near its post-open level.

Two regressions found and fixed while measuring: an appearance-observer redraw loop that pinned a full core, and a closed panel's hosting view that kept updating every sample.

## How to measure

```sh
pid=$(pgrep -x Glimpse)
ps -o etime,time,rss -p $pid        # CPU time over a known interval → average %
footprint $pid | grep Footprint      # Activity Monitor memory
top -l 2 -pid $pid -stats cpu,idlew,power | tail -1
sample Glimpse 3                      # where time goes if CPU is high
```

Not yet measured: eight-hour soak, Intel and macOS 12, low-power mode, sleep/wake, energy impact over a day, a universal Developer ID build.
