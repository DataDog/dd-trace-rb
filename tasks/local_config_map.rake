# frozen_string_literal: true

require 'json'
require 'pp' # rubocop:disable Lint/RedundantRequireStatement
require 'set'

# Pretty print setup
class Array
  def pretty_print(q)
    q.group(2, '[', ']') do # The only diff with original source code the offset that has been changed to 2 to comply to standard-rb.
      q.seplist(self) { |v| q.pp v }
    end
  end
end

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
  aliases = {}
  deprecations = Set.new
  alias_to_canonical = {}
  supported_configurations = data[:supportedConfigurations].each.with_object([]) do |(name, configs), result|
    configs.each do |config|
      config["aliases"]&.each do |alias_name|
        aliases[name] ||= Set.new
        aliases[name].add(alias_name)
        if alias_to_canonical[alias_name] && alias_to_canonical[alias_name] != name
          raise "The alias #{alias_name} is already used for #{alias_to_canonical[alias_name]}."
        end

        alias_to_canonical[alias_name] = name

        # If an alias is not registered as its own config, it is by default deprecated
        deprecations.add(alias_name) unless data.dig(:supportedConfigurations, alias_name)
      end
      # Add deprecated configs with no replacement provided
      deprecations.add(name) if config["deprecations"]
    end
    result << name
  end
  # Ignore comment field
  supported_configurations = supported_configurations.sort
  aliases = aliases.transform_values!(&:to_a).sort.to_h
  deprecations = deprecations.to_a.sort
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

        require 'set'

        # This file is auto-generated from `supported-configurations.json` by `rake local_config_map:generate`.
        # Do not change manually! Please refer to `docs/AccessEnvironmentVariables.md` for more information.

        module Datadog
          module Core
            module Configuration
              SUPPORTED_CONFIGURATIONS =
                Set#{ConfigPrinter.pp(supported_configurations)}.freeze

              ALIASES =
                #{ConfigPrinter.pp(aliases)}.freeze

              DEPRECATIONS =
                Set#{ConfigPrinter.pp(deprecations)}

              ALIAS_TO_CANONICAL =
                #{ConfigPrinter.pp(alias_to_canonical)}.freeze
            end
          end
        end
      RUBY
    )
  end
end
