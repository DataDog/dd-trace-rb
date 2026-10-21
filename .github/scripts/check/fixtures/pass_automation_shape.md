<!-- expect: -->
### Why

Routine maintenance: system tests CI runs against a pinned system-tests commit. This PR moves the pin upstream.

### What

Updates the system-tests reference to commit [abc1234](https://github.com/DataDog/system-tests/commit/abc1234).

### Risk

Two-way door, CI-only reference. Before merging, confirm the commit is merged into system-tests main.

### Details

Reviewer action: merge when CI is green.

<details><summary>Automation</summary>

- Event: repository_dispatch
- Triggered by: images-rb
- Source repo: DataDog/system-tests

</details>
