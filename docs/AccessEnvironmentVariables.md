# Access environment variables through Central Configuration Inversion

This document explains how to properly access environment variables and manage configuration in the dd-trace-rb library with the central configuration inversion initiative.

## Overview

The dd-trace-rb library implements **central configuration inversion** through the `ConfigHelper` module to ensure all environment variable access is centralized, documented, and validated. This approach prevents direct `ENV` access and enforces that all supported environment variables are properly registered.

Central configuration inversion name means that there is a single, centralized source of truth for configuration, and libraries use that source to accept configurations or not. This inverts the previous process, where configurations were defined in each library and we attempted to create a source of truth from the existing code, often leading to incomplete documentation.

## Key Components

### 1. Environment variables access

Instead of accessing `ENV` directly, use `DATADOG_ENV` to read environment variables:

```ruby
# ❌ Bad: Direct ENV access
api_key = ENV['DD_API_KEY']
service = ENV.fetch('DD_SERVICE', 'default_service')
timeout = ENV.fetch('DD_TIMEOUT') do |key|
  "#{key} not found"
end
has_service = ENV.key?('DD_SERVICE')

# ✅ Good: Using DATADOG_ENV
api_key = DATADOG_ENV['DD_API_KEY']
service = DATADOG_ENV.fetch('DD_SERVICE', 'default_service')
timeout = DATADOG_ENV.fetch('DD_TIMEOUT', '30') do |key|
  "#{key} not found"
end
has_service = DATADOG_ENV.key?('DD_SERVICE')
```

For rare cases where your code is outside of Datadog namespace, use `Datadog::DATADOG_ENV`.

This is enforced by the `CustomCops::EnvUsageCop` cop.

### 2. Supported Configurations Registry

All environment variables that start with `DD_` or `OTEL_` must be registered in the `supported-configurations.json` file to be accessible through `DATADOG_ENV`.

### 3. Automatic Code Enforcement

Custom RuboCop cops automatically detect and prevent direct `ENV` usage:

- `CustomCops::EnvUsageCop` - Prevents direct `ENV` access and auto-corrects to use `DATADOG_ENV`
- `CustomCops::EnvStringValidationCop` - Validates that environment variable strings are registered in supported configurations

## How It Works

The configuration inversion system works as follows:

1. **Environment Variable Request**: Code calls `DATADOG_ENV['DD_SOME_VAR']`
2. **Validation**: The `ConfigHelper` checks if the variable is in the supported configurations
3. **Access Control**:
   - If the variable starts with `DD_` or `OTEL_` but is NOT in supported configurations → returns `nil` (or raises error in test environment)
   - If the variable is supported or doesn't start with `DD_`/`OTEL_` and is not an alias → returns the value
4. **Alias Resolution**: Checks for any configured aliases if the primary variable is not set
5. **Deprecation Logging**: Logs deprecation warnings for deprecated variables

## Adding New Environment Variables

To add support for a new environment variable:

### Step 1: Add to supported-configurations.json & central registry

If the configuration key has never been registered by any tracer it needs to be added to the [Configuration Registry](https://feature-parity.us1.prod.dog/#/configurations?viewType=configurations) (available only for internal contributors) with proper documentation. In the case of an already existing key the behavior needs to be verified in order to know if a new version of the same key needs to be created on the registry.

Edit the `supported-configurations.json` file and add your variable (Please keep any new keys in the file sorted!):

```json
{
  "supportedConfigurations": {
    "DD_YOUR_NEW_VARIABLE": [
      {
        "version": "A",
        "type": "boolean",
        "propertyKeys": ["tracing.new_variable"],
        "defaultValue": "true",
        "aliases": ["DD_ALIAS_1", "DD_ALIAS_2"],
        "deprecated": true
      }
    ]
  }
}
```

#### Configuration Structure

- **supportedConfigurations**: Maps variable names to configuration metadata. For now, we only support a single version per configuration but it is an array for future usage.
  - `version`: String indicating which implementations the tracer supports. Implementations are defined in the Configuration Registry. Versions are non-numeric to avoid confusion with library versions.
  - `type`: Optional, one of `boolean | int | float | string | array | map`. Indicates the type of the configuration value. This will tells the parser how to parse the environment variable value.
  - `propertyKeys`: Optional, array containing a single value, the path to access the configuration from `Datadog.configuration`. This is an array for future usage.
  - `defaultValue`: Optional, the default value, as a string, that will be parsed like an environment variable value.
  - `aliases`: Optional, maps the config to an array of alias names. These environment variables should not be used in dd-trace-rb code. These aliases are by default considered deprecated. To accept non-deprecated environment variables, you must also add them as a separate configuration.
  - `deprecated`: Optional, true | false, adds a log message to deprecated environment variables.

### Step 2: Generate Configuration Assets

This step requires Ruby 3.4 or higher due to the change in the format of
generated JSON output.

Run the rake task to generate the Ruby configuration assets:

```bash
bundle exec rake local_config_map:generate
```

This task generates `lib/datadog/core/configuration/supported_configurations.rb` ahead of time, so the tracer does not need to parse the JSON file every time.

## RuboCop Integration

The custom cops will automatically:

### Detect Direct ENV Usage

```ruby
# This will be flagged by CustomCops/EnvUsageCop
api_key = ENV['DD_API_KEY']
# Auto-corrected to:
api_key = DATADOG_ENV['DD_API_KEY']
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
  DATADOG_ENV['DD_UNSUPPORTED_VAR']
rescue RuntimeError => e
  puts e.message # "Missing DD_UNSUPPORTED_VAR env/configuration in "supported-configurations.json" file."
end
```

### CI jobs

#### Local file validation

The `validate_supported_configurations_local_file` CI job in charge of validating the content of the `supported-configurations.json` file against the central Configuration Registry runs on GitLab in the `shared-pipeline` stage. This job verifies that all configuration keys present in the local file are correctly registered on the central registry. When a new key is introduced it has to be registered in order to pass this job.

Example of a failed run output:

```json
Missing properties:
{
  "DD_TRACE_GRAPHQL_ERROR_TRACKING": [
    "A"
  ]
}
The above configuration was found locally but missing from the configuration registry.
```

#### Updating supported versions

The `update_central_configurations_version_range` CI job runs upon tagging a new release. This job updates the central registry with the new version released indicating newly supported or dropped configuration keys.

## Validation

To ensure your configuration changes are valid:

```bash
# Validate that generated assets match the JSON file
bundle exec rspec spec/datadog/core/configuration/supported_configurations_spec.rb
```

This will also be run by the main RSpec rake task.

This task will exit with an error if there's a mismatch between `supported-configurations.json` and the generated assets. It is run by the CI, thus a mismatch will make the CI fail.

## Troubleshooting

### "Missing X env/configuration in supported-configurations.json file"

This error indicates you're trying to access a `DD_` or `OTEL_` environment variable that's not registered. Add it to `supported-configurations.json` and regenerate assets.

### RuboCop Cop Violations

- `CustomCops/EnvUsageCop`: You're using direct `ENV` access. Replace with `DATADOG_ENV`
- `CustomCops/EnvStringValidationCop`: You have a string that looks like an env var but isn't registered. Either add it to supported configurations or disable the cop if it's a false positive.

### Configuration Mismatch Warning

If you see "Configuration map mismatch between the JSON file and the generated file" in the CI, run:

```bash
bundle exec rake local_config_map:generate
```

And commit the updated generated file.
