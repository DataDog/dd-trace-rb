# Custom RuboCop Cops

This directory contains custom RuboCop cops for the dd-trace-rb project.

## EnvUsageCop

The `CustomCops::EnvUsageCop` prevents direct usage of the `ENV` hash to access environment variables.

### Purpose

This cop prohibits usage of `ENV` and automatically corrects it to use `DATADOG_ENV`. This ensures that environment variable usage is documented and follows the proper Datadog configuration pattern.

### Examples

#### Bad: Direct ENV usage

```ruby
# These will trigger offenses:
module Datadog
  api_key = ENV['DD_API_KEY']
  debug_mode = ENV['DEBUG']
  timeout = ENV.fetch('TIMEOUT', '30')

  if ENV.key?('DD_API_KEY')
    puts 'API key is set'
  end

  puts "API Key: #{ENV['DD_API_KEY']}"

  config = {
    api_key: ENV['DD_API_KEY'],
    debug: ENV['DEBUG']
  }
end
enabled = ENV['DD_TRACE_ENABLED']
```

#### Good: Using `DATADOG_ENV`

```ruby
# These are the corrected versions:
module Datadog
  api_key = DATADOG_ENV['DATADOG_API_KEY']
  debug_mode = DATADOG_ENV['DEBUG']
  # Supports default value like ENV.fetch
  timeout = DATADOG_ENV.fetch('TIMEOUT', '30')

  if DATADOG_ENV.key?('DATADOG_API_KEY')
    puts 'API key is set'
  end

  puts "API Key: #{DATADOG_ENV['DATADOG_API_KEY']}"

  config = {
    api_key: DATADOG_ENV['DATADOG_API_KEY'],
    debug: DATADOG_ENV['DEBUG']
  }
end
enabled = Datadog::DATADOG_ENV['DD_TRACE_ENABLED']
```

### Auto-correction

The cop automatically corrects the following patterns:

- `ENV['key']` → `DATADOG_ENV['key']`
- `ENV.fetch('key')` → `DATADOG_ENV.fetch('key')`
- `ENV.fetch('key', default)` → `DATADOG_ENV.fetch('key', default)`
- `ENV.fetch('key') { |k| return k }` → `DATADOG_ENV.fetch('key')  { |k| return k }`
- `ENV.key?('key')` → `DATADOG_ENV.key?('key')`
- `ENV.has_key?('key')` → `DATADOG_ENV.has_key?('key')`
- `ENV.include?('key')` → `DATADOG_ENV.include?('key')`
- `ENV.member?('key')` → `DATADOG_ENV.member?('key')`

For `ENV` access outside of Datadog namespace, it will also autocorrect to `Datadog::DATADOG_ENV`

### Testing

Run the cop tests with:

```bash
bundle exec rspec spec/custom_cops/env_usage_cop_spec.rb
```

## EnvStringValidationCop

The `CustomCops::EnvStringValidationCop` validates environment variable strings starting with `DD_` or `OTEL_` against the list of supported configurations.

### Purpose

This cop helps ensure that all environment variable strings (literal strings that look like Datadog or OpenTelemetry environment variables) are valid and documented. It validates against `SUPPORTED_CONFIGURATION_NAMES`, `ALIASES` and `DEPRECATIONS` from `lib/datadog/core/configuration/supported_configurations.rb`, which contains all officially supported environment variables and their aliases.

The cop may produce false positives for strings that are not actually used as environment variables but follow the naming pattern (e.g., telemetry keys, log messages). In such cases, you can disable the cop for specific lines with `# rubocop:disable CustomCops/EnvStringValidationCop`

### Pattern Detection

The cop detects strings that match the pattern:
- Start with `DD_` or `OTEL_`
- Followed by at least one uppercase letter
- Contain only uppercase letters, numbers, and underscores

### Examples

#### Bad: Unknown environment variable strings

```ruby
# These will trigger offenses if not in the supported configurations:
config_value = "DD_CUSTOM_ENV_VAR"
settings = {
  api_key: "DD_NONEXISTENT_KEY"
}

# OpenTelemetry variables are also checked:
otel_config = "OTEL_CUSTOM_SETTING"
```

#### Good: Known environment variable strings

```ruby
# These are allowed (from supported configurations):
api_key = "DD_API_KEY"
service_name = "DD_SERVICE"
trace_enabled = "DD_TRACE_ENABLED"
otel_service = "OTEL_SERVICE_NAME"
otel_sampler = "OTEL_TRACES_SAMPLER"
```

### Handling False Positives

For legitimate strings that are not environment variables but match the pattern:

```ruby
# False positive: telemetry key that looks like an env var
telemetry_data = {
  "DD_AGENT_TRANSPORT" => transport_type # rubocop:disable CustomCops/EnvStringValidationCop
}

# False positive: log message containing env var pattern
logger.debug("Processing DD_CUSTOM_METRIC_NAME") # rubocop:disable CustomCops/EnvStringValidationCop
```

### Additional information

See docs/AccessEnvironmentVariables.md for details.
