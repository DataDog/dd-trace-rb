# Feature Flags Test Suite

This directory contains comprehensive tests for the Datadog Feature Flags functionality implemented via the `libdatadog_api` C extension.

## Test Structure

### Test Files

- **`feature_flags_spec.rb`** - Core functionality tests and JSON test case execution
- **`flag_types_spec.rb`** - Enhanced flag type support (boolean, numeric, JSON) and backward compatibility
- **`test_case_runner_spec.rb`** - Comprehensive test case runner that validates against all libdatadog test cases
- **`feature_flags_integration_spec.rb`** - Integration tests and smoke tests

### Support Files

- **`spec/support/feature_flags_helpers.rb`** - Test helper methods and utilities
- **`fixtures/`** - JSON test data copied from libdatadog repository

## Test Data

The `fixtures/` directory contains:

- **`flags-v1.json`** - Main feature flag configuration file (77KB+ with comprehensive flag definitions)
- **`test-case-*.json`** - Individual test case files covering:
  - Boolean attribute matching
  - Disabled flags
  - Empty flags
  - Integer flags
  - JSON/Object flags
  - Kill switch behavior
  - Special character handling
  - Edge cases and error conditions

Total: **20+ test files** with **50+ individual test cases**

## Running Tests

### Prerequisites

1. **libdatadog gem** must be installed and compatible with your platform
2. **libdatadog_api extension** must compile successfully
3. Ruby version compatibility (typically Ruby 2.7+)

### Individual Test Suites

```bash
# Core functionality tests
bundle exec rspec spec/datadog/core/feature_flags/feature_flags_spec.rb

# Flag type tests (enhanced features)
bundle exec rspec spec/datadog/core/feature_flags/flag_types_spec.rb

# Comprehensive test case validation
bundle exec rspec spec/datadog/core/feature_flags/test_case_runner_spec.rb

# Integration and smoke tests
bundle exec rspec spec/datadog/core/feature_flags_integration_spec.rb
```

### All Feature Flag Tests

```bash
# Run all feature flag tests
bundle exec rspec spec/datadog/core/feature_flags/

# Or with tag filtering
bundle exec rspec --tag feature_flags
```

## What The Tests Validate

### Core Functionality

- ✅ **Configuration Loading** - JSON parsing and configuration creation
- ✅ **Flag Evaluation** - Basic get_assignment functionality
- ✅ **Context Handling** - User context and attribute processing
- ✅ **Error Handling** - Invalid configurations and missing flags

### Enhanced Features (if available)

- ✅ **Multiple Flag Types** - Boolean, String, Number, Object support
- ✅ **Type-Specific Evaluation** - Flag type constants and 3-parameter API
- ✅ **Backward Compatibility** - Original 2-parameter method still works

### OpenFeature Compliance

- ✅ **Standard Reasons** - UPPERCASE string constants (STATIC, DEFAULT, etc.)
- ✅ **Standard Error Codes** - UPPERCASE error codes (TYPE_MISMATCH, etc.)
- ✅ **Resolution Details** - Complete ResolutionDetails object structure

### Performance & Safety

- ✅ **Memory Safety** - GC safety improvements for string handling
- ✅ **Performance** - Optimized hash iteration
- ✅ **Load Testing** - Multiple rapid evaluations
- ✅ **Large Context** - Handling of large attribute sets

### Cross-Language Validation

- ✅ **libdatadog Compatibility** - All test cases from Rust implementation
- ✅ **Expected Results** - Validates against known good outputs
- ✅ **Edge Cases** - Comprehensive edge case coverage

## Test Output Examples

### Successful Run

```
Feature Flags Integration Tests
  Extension availability
    ✓ loads the libdatadog_api extension successfully
    ✓ has working Configuration class
    ✓ has working ResolutionDetails methods

  Test data availability
    ✓ has the main configuration file
    ✓ has test case files
    ✓ can parse all test files as valid JSON

Finished in 0.12 seconds (files took 0.8 seconds to load)
8 examples, 0 failures
```

### Extension Not Available

```
Feature Flags Integration Tests
  Extension availability (PENDING: libdatadog_api extension not available)

Finished in 0.01 seconds (files took 0.5 seconds to load)
8 examples, 0 failures, 8 pending
```

## Implementation Coverage

The tests are designed to work with both:

1. **Original Implementation** - Basic string flag support
2. **Enhanced Implementation** - Multiple flag types, improved performance, OpenFeature compliance

Tests automatically detect available features and adjust expectations accordingly.

## Debugging Test Failures

### Extension Loading Issues

If tests skip with "libdatadog_api extension not available":

1. Check if `libdatadog` gem is installed: `bundle list | grep libdatadog`
2. Verify platform compatibility (ARM64 macOS may have issues)
3. Compile extension manually: `cd ext/libdatadog_api && ruby extconf.rb && make`

### Configuration Errors

If configuration creation fails:
- Check libdatadog version compatibility
- Verify JSON test data integrity
- Look for missing dependencies

### Evaluation Failures

If specific test cases fail:
- Compare with expected results in JSON files
- Check for implementation differences between Ruby and Rust
- Validate context attribute handling

## Contributing

When adding new tests:

1. Use the `FeatureFlagsHelpers` module for common functionality
2. Add `with_feature_flags_extension` to skip when extension unavailable
3. Test both original and enhanced API methods when possible
4. Follow the naming convention: `*_spec.rb` for test files
5. Update this README if adding new test categories