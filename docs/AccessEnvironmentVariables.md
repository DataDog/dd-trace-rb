# Access environment variables through Central Configuration Inversion

This document explains how to properly access environment variables and manage configuration in the dd-trace-rb library with the central configuration inversion initiative.

## Overview

The dd-trace-rb library implements **central configuration inversion** through the `ConfigHelper` module to ensure all environment variable access is centralized, documented, and validated. This approach prevents direct `ENV` access and enforces that all supported environment variables are properly registered.

Central configuration inversion name means that there is a single, centralized source of truth for configuration, and tracers uses that source to accept configurations or not. This inverts the previous process, where configurations were defined in each tracers and we attempted to create a source of truth  existing code, often leading to incomplete documentation.

## Key Components

### 1. Environment variables access

Instead of accessing `ENV` directly, use `Datadog.get_environment_variable` to read environment variables:

```ruby
# ❌ Bad: Direct ENV access
api_key = ENV['DD_API_KEY']
timeout = ENV.fetch('DD_TIMEOUT', '30')

# ✅ Good: Using Datadog.get_environment_variable
api_key = Datadog.get_environment_variable('DD_API_KEY')
timeout = Datadog.get_environment_variable('DD_TIMEOUT') || '30'
```

This is enforced by the `CustomCops::EnvUsageCop` cop.

### 2. Supported Configurations Registry

All environment variables that start with `DD_` or `OTEL_` must be registered in the `supported-configurations.json` file to be accessible through `Datadog.get_environment_variable`.

### 3. Automatic Code Enforcement

Custom RuboCop cops automatically detect and prevent direct `ENV` usage:

- `CustomCops::EnvUsageCop` - Prevents direct `ENV` access and auto-corrects to use `Datadog.get_environment_variable`
- `CustomCops::EnvStringValidationCop` - Validates that environment variable strings are registered in supported configurations

## How It Works

The configuration inversion system works as follows:

1. **Environment Variable Request**: Code calls `Datadog.get_environment_variable('DD_SOME_VAR')`
2. **Validation**: The `ConfigHelper` checks if the variable is in the supported configurations
3. **Access Control**:
   - If the variable starts with `DD_` or `OTEL_` but is NOT in supported configurations → returns `nil` (or raises error in test environment)
   - If the variable is supported or doesn't start with `DD_`/`OTEL_` and is not an alias → returns the value
4. **Alias Resolution**: Checks for any configured aliases if the primary variable is not set
5. **Deprecation Logging**: Logs deprecation warnings for deprecated variables

## Adding New Environment Variables

To add support for a new environment variable:

### Step 1: Add to supported-configurations.json

Edit the `supported-configurations.json` file and add your variable:

```json
{
  "supportedConfigurations": {
    "DD_YOUR_NEW_VARIABLE": {
      "version": ["A"]
    }
  }
}
```

#### Configuration Structure

- **supportedConfigurations**: Maps variable names to configuration metadata
  - `version`: (Currently always set to `["A"]`) Array indicating which tracer versions change the behavior of the configuration

  In the future, the structure will also contain more information such as the type, the default value...

- **aliases**: Maps canonical variable names to arrays of alias names
  ```json
  "aliases": {
    "DD_SERVICE": ["OTEL_SERVICE_NAME"]
  }
  ```

- **deprecations**: Adds a log message to deprecated environment variables.
  ```json
  "deprecations": {
    "DD_OLD_VARIABLE": "Please use DD_NEW_VARIABLE",
    "DD_REMOVED_VARIABLE": "This feature will be removed in the next release"
  }
  ```

### Step 2: Generate Configuration Assets

Run the rake task to generate the Ruby configuration assets:

```bash
bundle exec rake local_config_map:generate
```

This task generates `lib/datadog/core/configuration/assets/supported_configurations.rb` ahead of time, so the tracer does not need to parse the JSON file every time.

## RuboCop Integration

The custom cops will automatically:

### Detect Direct ENV Usage

```ruby
# This will be flagged by CustomCops/EnvUsageCop
api_key = ENV['DD_API_KEY']
# Auto-corrected to:
api_key = Datadog.get_environment_variable('DD_API_KEY')
```

### Validate Environment Variable Strings

```ruby
# This will be flagged by CustomCops/EnvStringValidationCop if not in supported-configurations.json
config_key = "DD_UNSUPPORTED_VARIABLE"
```

To disable cop checking for false positives (e.g., telemetry keys that look like env vars):

```ruby
# False positive: telemetry key that looks like an env var
telemetry_data = {
  "DD_AGENT_TRANSPORT" => transport_type # rubocop:disable CustomCops/EnvStringValidationCop
}
```

## Testing

In test environments, the system is stricter:

```ruby
# In tests, unsupported DD_/OTEL_ variables will raise errors
begin
  Datadog.get_environment_variable('DD_UNSUPPORTED_VAR')
rescue RuntimeError => e
  puts e.message # "Missing DD_UNSUPPORTED_VAR env/configuration in "supported-configurations.json" file."
end
```

## Validation

To ensure your configuration changes are valid:

```bash
# Validate that generated assets match the JSON file
bundle exec rake local_config_map:validate
```

This task will exit with an error if there's a mismatch between `supported-configurations.json` and the generated assets. It is run by the CI, thus a mismatch will make the CI fail.

## Troubleshooting

### "Missing X env/configuration in supported-configurations.json file"

This error indicates you're trying to access a `DD_` or `OTEL_` environment variable that's not registered. Add it to `supported-configurations.json` and regenerate assets.

### RuboCop Cop Violations

- `CustomCops/EnvUsageCop`: You're using direct `ENV` access. Replace with `Datadog.get_environment_variable`
- `CustomCops/EnvStringValidationCop`: You have a string that looks like an env var but isn't registered. Either add it to supported configurations or disable the cop if it's a false positive.

### Configuration Mismatch Warning

If you see "Configuration map mismatch between the JSON file and the generated file" in the CI, run:

```bash
bundle exec rake local_config_map:generate
```

And commit the updated generated file.
