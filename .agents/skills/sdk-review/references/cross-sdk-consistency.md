# Cross-SDK consistency

Behaviour that must match other Datadog SDKs, specs (including OpenTelemetry), and the agent or backend contract.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line, or when it clearly diverges from a spec or another SDK in a way no rule covers (mark it `no rule`), naming the spec, registry, or contract you compared against. Only the cross-SDK reviewer may consult external references.

- Check changes to shared tracer behavior (e.g., context propagation, sampling, configuration, or telemetry) for cross-language impact, using relevant specifications and other tracer implementations as references.
- When an issue stems from the shared design or specification, explicitly flag it as a **design issue** requiring coordination with the affected tracer teams.
- Explain why a Ruby-only fix is insufficient or would create divergence.
- Distinguish this from a Ruby implementation bug that can be fixed locally to match the agreed behavior.
- Validation across all dd-trace- repositories is not required.

Other repositories:
- [.NET (`dd-trace-dotnet`)](https://github.com/DataDog/dd-trace-dotnet)
- [Java (`dd-trace-java`)](https://github.com/DataDog/dd-trace-java)
- [Python (`dd-trace-py`)](https://github.com/DataDog/dd-trace-py)
- [Node.js (`dd-trace-js`)](https://github.com/DataDog/dd-trace-js)
- [Go (`dd-trace-go`)](https://github.com/DataDog/dd-trace-go)
- [PHP (`dd-trace-php`)](https://github.com/DataDog/dd-trace-php)
- [C++ (`dd-trace-cpp`)](https://github.com/DataDog/dd-trace-cpp)
- [Rust (`libdatadog`)](https://github.com/DataDog/libdatadog)

## 1. Configuration

### XSDK-1.1: Keep env var names identical to other Datadog SDKs
- Flag: a new `DD_*` env var whose name differs from the one other SDKs already use for the same setting, including expanding an abbreviation (`CTX`) or dropping an `EXPERIMENTAL` prefix.
- Not when: no other SDK defines the setting yet; then follow the product's `DD_<PRODUCT>_*` prefix.

### XSDK-1.2: Check whether a cross-SDK spec fixes a public module or constant name before renaming it
- Flag: a rename of a shipped public namespace or class (for example, `Datadog::OpenFeature::Provider`) with no reference to the cross-SDK spec or other SDKs' names.

## Don't flag
- Warn-and-fall-back parsing of invalid env var values when other SDKs handle them the same way.
- Ruby settings namespaces that differ from other SDKs; only env var names are the shared contract.
