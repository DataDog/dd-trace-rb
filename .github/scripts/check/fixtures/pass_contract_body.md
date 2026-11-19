<!-- expect: -->
### Why

Dynamic Instrumentation's capture budget was measured in wall-clock time, so time the thread spent descheduled or waiting counted against it, and captures could time out without the serializer actually doing that much work. This affects any customer environment with thread contention or scheduling delays.

### What

The DI capture serialization budget is now measured in thread CPU time, so it expires only on CPU actually consumed by serialization. Timeout behavior and configuration are otherwise unchanged.

### Risk

Two-way door, scoped to DI capture serialization. Revert the commit to restore wall-clock budgeting; no data format or settings changes.

### Details

<details><summary>Automation</summary>

Internal change to DI capture timing semantics. No changelog fragment was added.

</details>
