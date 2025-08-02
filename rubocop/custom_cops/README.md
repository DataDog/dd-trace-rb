# Custom RuboCop Cops

This directory contains custom RuboCop cops for the dd-trace-rb project.

## EnvUsageCop

The `CustomCops::EnvUsageCop` prevents direct usage of the `ENV` hash to access environment variables.

### Purpose

This cop prohibits usage of `ENV` and automatically corrects it to use `Datadog.get_environment_variable`. This ensures that environment variable usage is documented and follows the proper Datadog configuration pattern.

### Examples

#### Bad: Direct ENV usage

```ruby
# These will trigger offenses:
api_key = ENV['DATADOG_API_KEY']
debug_mode = ENV['DEBUG']
timeout = ENV.fetch('TIMEOUT', '30')

if ENV.key?('DATADOG_API_KEY')
  puts 'API key is set'
end

puts "API Key: #{ENV['DATADOG_API_KEY']}"

config = {
  api_key: ENV['DATADOG_API_KEY'],
  debug: ENV['DEBUG']
}
```

#### Good: Using `Datadog.get_environment_variable`

```ruby
# These are the corrected versions:
api_key = Datadog.get_environment_variable('DATADOG_API_KEY')
debug_mode = Datadog.get_environment_variable('DEBUG')
timeout = Datadog.get_environment_variable('TIMEOUT') || '30'

if !Datadog.get_environment_variable('DATADOG_API_KEY').nil?
  puts 'API key is set'
end

puts "API Key: #{Datadog.get_environment_variable('DATADOG_API_KEY')}"

config = {
  api_key: Datadog.get_environment_variable('DATADOG_API_KEY'),
  debug: Datadog.get_environment_variable('DEBUG')
}
```

### Auto-correction

The cop automatically corrects the following patterns:

- `ENV['key']` → `Datadog.get_environment_variable('key')`
- `ENV.fetch('key')` → `Datadog.get_environment_variable('key')`
- `ENV.fetch('key', default)` → `Datadog.get_environment_variable('key') || default`
- `ENV.key?('key')` → `!Datadog.get_environment_variable('key').nil?`
- `ENV.has_key?('key')` → `!Datadog.get_environment_variable('key').nil?`
- `ENV.include?('key')` → `!Datadog.get_environment_variable('key').nil?`
- `ENV.member?('key')` → `!Datadog.get_environment_variable('key').nil?`
- `ENV.values` → `Datadog.get_environment_variables.values`
- `ENV.keys` → `Datadog.get_environment_variables.keys`

### Configuration

The cop is enabled by default in `.customcops.yml`:

```yaml
CustomCops/EnvUsageCop:
  Enabled: true
  Description: 'Prevents direct usage of ENV to access environment variables'
```

This file is included in `.rubocop.yml` and `.standard.yml`

### Testing

Run the cop tests with:

```bash
bundle exec rspec spec/custom_cops/env_usage_cop_spec.rb
```
