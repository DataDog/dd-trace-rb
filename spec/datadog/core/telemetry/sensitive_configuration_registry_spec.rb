require 'spec_helper'

require 'json'

# Drift guard between the code and the configuration registry.
#
# Two sources of truth must agree about which configurations are sensitive:
#   1. The code: options whose definition declares `skip_telemetry true`.
#   2. The registry: entries marked `"sensitive": true` in supported-configurations.json.
#
# This spec asserts the two sets are consistent so that adding a new sensitive
# configuration without the flag (or marking the flag without the registry, or
# vice versa) fails loudly.
#
# Scope: the comparison is limited to env-var-backed options. Some `skip_telemetry`
# options have no environment variable and exist purely to control how the value is
# reported, not because the value is sensitive (e.g. `logger.instance`, which is
# re-added manually under its own name, and `tracing.writer_options`, which is split
# into per-key entries). Those have no registry key to compare against, so they are
# intentionally excluded from this 1:1 mapping.
RSpec.describe 'sensitive configuration registry drift' do
  # Recursively yield every leaf (non-settings) option in the live settings tree.
  def each_leaf_option(settings, &block)
    settings.class.options.each_key do |name|
      option = settings.send(:resolve_option, name)
      if option.settings?
        each_leaf_option(option.get, &block)
      else
        block.call(option)
      end
    end
  end

  # Recursively collect registry keys that have any version marked sensitive.
  def collect_sensitive_registry_keys(object)
    keys = []
    return keys unless object.is_a?(Hash)

    object.each do |key, value|
      if value.is_a?(Array) && value.any? { |entry| entry.is_a?(Hash) && entry['sensitive'] }
        keys << key
      elsif value.is_a?(Hash)
        keys.concat(collect_sensitive_registry_keys(value))
      end
    end

    keys
  end

  let(:skip_telemetry_env_keys) do
    keys = []
    each_leaf_option(Datadog.configuration) do |option|
      next unless option.definition.skip_telemetry

      env = option.definition.env
      keys << env if env
    end
    keys.sort
  end

  let(:registry_sensitive_keys) do
    registry_path = File.expand_path('../../../../supported-configurations.json', __dir__)
    registry = JSON.parse(File.read(registry_path))
    collect_sensitive_registry_keys(registry).sort
  end

  it 'keeps the skip_telemetry and registry-sensitive sets identical' do
    missing_from_registry = skip_telemetry_env_keys - registry_sensitive_keys
    missing_from_code = registry_sensitive_keys - skip_telemetry_env_keys

    expect(skip_telemetry_env_keys).to eq(registry_sensitive_keys),
      "skip_telemetry options and registry-sensitive keys have drifted. " \
      "Declared `skip_telemetry true` but not marked `\"sensitive\": true` in " \
      "supported-configurations.json: #{missing_from_registry.inspect}. " \
      "Marked `\"sensitive\": true` in supported-configurations.json but no option declares " \
      "`skip_telemetry true`: #{missing_from_code.inspect}."
  end
end
