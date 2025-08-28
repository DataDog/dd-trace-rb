# frozen_string_literal: true

require 'json'
require 'pp' # rubocop:disable Lint/RedundantRequireStatement

# Pretty print setup
class ConfigPrinter < ::PP
  def self.pp(data)
    output = +''
    q = new(output, 124)
    q.group(8) do
      q.pp(data)
    end
    q.flush
    output
  end
end

namespace :local_config_map do
  # We only keep env vars as strings
  data = JSON.parse(File.read('supported-configurations.json')).transform_keys(&:to_sym)
  data[:supportedConfigurations].each_value { |config| config.transform_keys!(&:to_sym) }
  alias_to_canonical = data[:aliases].each_with_object({}) do |(canonical, alias_list), h|
    alias_list.each do |alias_name|
      raise "The alias #{alias_name} is already used for #{h[alias_name]}." if h[alias_name]

      h[alias_name] = canonical
    end
  end
  # Ignore comment field
  data = data.map { |k, v| [k, v.is_a?(Hash) ? v.sort.to_h : v] }.to_h
  alias_to_canonical = alias_to_canonical.sort.to_h

  # Read the data from the JSON file and generate ahead-of-time map for supported configurations, aliases and deprecations
  desc 'Generate the supported configurations, aliases and deprecations map'
  task :generate do
    # On versions older than 3.4, the result would look like {:key=>'value'}
    raise('Please run this task on Ruby >= 3.4') unless RUBY_VERSION >= '3.4'
    File.write(
      'lib/datadog/core/configuration/supported_configurations.rb',
      <<~RUBY
        # frozen_string_literal: true

        # This file is auto-generated from `supported-configurations.json` by `rake local_config_map:generate`.
        # Do not change manually! Please refer to `docs/AccessEnvironmentVariables.md` for more information.

        module Datadog
          module Core
            module Configuration
              SUPPORTED_CONFIGURATIONS =
                #{ConfigPrinter.pp(data[:supportedConfigurations])}.freeze

              ALIASES =
                #{ConfigPrinter.pp(data[:aliases])}.freeze

              DEPRECATIONS =
                #{ConfigPrinter.pp(data[:deprecations])}.freeze

              ALIAS_TO_CANONICAL =
                #{ConfigPrinter.pp(alias_to_canonical)}.freeze
            end
          end
        end
      RUBY
    )
  end
end
