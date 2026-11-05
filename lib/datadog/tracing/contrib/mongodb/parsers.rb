# frozen_string_literal: true

require_relative "../utils/quantization/hash_formatter"

module Datadog
  module Tracing
    module Contrib
      # MongoDB module includes classes and functions to instrument MongoDB clients
      module MongoDB
        EXCLUDE_KEYS = [:_id].freeze
        SHOW_KEYS = [].freeze
        DEFAULT_OPTIONS = {exclude: EXCLUDE_KEYS, show: SHOW_KEYS}.freeze

        # skipped keys are related to command names, since they are already
        # extracted by the query_builder
        PLACEHOLDER = "?"

        # returns a formatted and normalized query
        def self.query_builder(command_name, database_name, command)
          # always exclude the command name
          options = Contrib::Utils::Quantization::HashFormatter.merge_options(quantization_options, exclude: [command_name.to_s])

          base_info = Contrib::Utils::Quantization::HashFormatter.format(
            {
              "operation" => command_name,
              "database" => database_name,
              "collection" => command.values.first,
            },
            options,
          )

          base_info.merge(Contrib::Utils::Quantization::HashFormatter.format(command, options))
        end

        def self.quantization_options
          Contrib::Utils::Quantization::HashFormatter.merge_options(DEFAULT_OPTIONS, configuration[:quantize])
        end

        def self.configuration
          Datadog.configuration.tracing[:mongo]
        end
      end
    end
  end
end
