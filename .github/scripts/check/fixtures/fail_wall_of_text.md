<!-- expect: '### What' has -->
### Why

A wall-clock budget means a capture can be truncated merely because the thread was descheduled (garbage collection, OS scheduling, other threads) even though DI did very little actual work, so the budget did not measure what it is meant to limit.

### What

Measures the capture timeout budget in thread CPU time. Updates the shared spec helper stub_monotonic_clock into stub_cpu_clock, which stubs only thread CPU clock reads and passes other clock reads through unchanged. Adjusts the circuit breaker spec to raise the capture budget instead of freezing the monotonic clock, since the budget and the breaker now read the same clock.

### Risk

Two-way door, scoped to DI. Revert restores the previous clock.
