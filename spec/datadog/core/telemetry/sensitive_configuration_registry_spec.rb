require 'spec_helper'

require 'json'

# Drift guard: options declaring `skip_telemetry true` must match the entries marked
# `"sensitive": true` in supported-configurations.json, so adding one without the other
# fails loudly. Compared on env-var-backed options only; skip_telemetry options without an
# env var (e.g. logger.instance, tracing.writer_options) have no registry key.
RSpec.describe 'sensitive configuration registry drift' do
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
