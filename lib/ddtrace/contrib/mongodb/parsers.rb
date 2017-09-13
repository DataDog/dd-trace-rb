module Datadog
  module Contrib
    # MongoDB module includes classes and functions to instrument MongoDB clients
    module MongoDB
      module_function

      # skipped keys are related to command names, since they are already
      # extracted by the query_builder
      SKIP_KEYS = [:_id].freeze
      PLACEHOLDER = '?'.freeze

      # returns a formatted and normalized query
      def query_builder(command_name, database_name, command)
        # always skip the command name
        skip = SKIP_KEYS | [command_name.to_s]

        result = {
          operation: command_name,
          database: database_name,
          collection: command.values.first
        }

        command.each do |key, value|
          result[key] = normalize_statement(value, skip) unless skip.include?(key)
        end

        result
      end

      # removes the values from the given query; this quantization recursively
      # replace elements available in a given query, so that Arrays, Hashes and so
      # on are compacted. It ensures a low cardinality so that it can be used
      # as a Span resource.
      # TODO: the quantization may not be enough, we still need to check the
      # cardinality if it's reasonable
      def normalize_statement(source, skip = [])
        if source.is_a? Hash
          obfuscated = {}
          source.each do |key, value|
            obfuscated[key] = normalize_value(value, skip) unless skip.include?(key)
          end

          obfuscated
        else
          normalize_value(source, skip)
        end
      end

      def normalize_value(value, skip = [])
        if value.is_a?(Hash)
          normalize_statement(value, skip)
        elsif value.is_a?(Array)
          normalize_value(value.first, skip)
        else
          PLACEHOLDER
        end
      end
    end
  end
end
