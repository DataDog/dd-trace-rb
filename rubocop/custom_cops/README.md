# Custom RuboCop Cops

This directory contains custom RuboCop cops for the dd-trace-rb project.

## EnvUsageCop

The `CustomCops::EnvUsageCop` prevents direct usage of the `ENV` hash to access environment variables.

### Purpose

This cop prohibits usage of `ENV`. This ensures that environment variable usage is documented. TODO: Suggest/Replace with `get_environment_variable`

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

#### Good: Using `get_environment_variable`

TODO

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

### Auto-correction

Auto-correction is not implemented yet.