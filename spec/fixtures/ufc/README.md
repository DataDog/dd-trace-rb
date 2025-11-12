# Feature Flag Configuration Test Fixtures

This directory contains test fixtures for Datadog Feature Flags.

## Source

These test fixtures originate from the [system-tests project](https://github.com/DataDog/system-tests/blob/main/tests/parametric/test_feature_flag_exposure), where they are used for cross-SDK compatibility testing. In production, this configuration is delivered via a remote config protocol wrapped as:

```json
{
  "path": "datadog/2/FFE_FLAGS/{config_id}/config",
  "msg": <contents of flags-v1.json>
}
```

## Directory Contents

- `flags-v1.json` - Main feature flag configuration fixture used across multiple test suites
- `test_cases/` - Individual test cases demonstrating various flag scenarios including:
  - Boolean, integer, numeric, and string flag variations
  - Targeting rules with different operators (ONE_OF, MATCHES, GTE, etc.)
  - Traffic splitting with shard ranges
  - Edge cases like disabled flags and empty configurations

## Configuration Format

The configuration format includes:
- **flags**: Feature flag definitions with variations and targeting rules
- **allocations**: Traffic splitting rules with shard-based distribution  
- **variations**: Different values a flag can return
- **rules**: Targeting conditions based on user attributes

This format ensures consistent feature flag behavior across all Datadog SDKs and is validated through system-tests.
