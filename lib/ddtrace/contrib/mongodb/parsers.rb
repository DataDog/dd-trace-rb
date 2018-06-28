module Datadog
  module Contrib
    # MongoDB module includes classes and functions to instrument MongoDB clients
    module MongoDB
      EXCLUDE_KEYS = [:_id].freeze
      SHOW_KEYS = [].freeze
      DEFAULT_OPTIONS = { exclude: EXCLUDE_KEYS, show: SHOW_KEYS }.freeze

      module_function

      # skipped keys are related to command names, since they are already
      # extracted by the query_builder
      PLACEHOLDER = '?'.freeze

      # returns a formatted and normalized query
      def query_builder(command_name, database_name, command)
        # always exclude the command name
        options = Quantization::Hash.merge_options(quantization_options, exclude: [command_name.to_s])

        # quantized statements keys are strings to avoid leaking Symbols in older Rubies
        # as Symbols are not GC'ed in Rubies prior to 2.2
        base_info = Quantization::Hash.format({
                                                'operation' => command_name,
                                                'database' => database_name,
                                                'collection' => command.values.first
                                              }, options)

        base_info.merge(Quantization::Hash.format(command, options))
      end

      # removes the values from the given query; this quantization recursively
      # replace elements available in a given query, so that Arrays, Hashes and so
      # on are compacted. It ensures a low cardinality so that it can be used
      # as a Span resource.
      # @deprecated
      def quantize_statement(statement, skip = [])
        case statement
        when Hash
          statement.each_with_object({}) do |(key, value), quantized|
            quantized[key] = quantize_value(value, skip) unless skip.include?(key)
          end
        else
          quantize_value(statement, skip)
        end
      end

      # @deprecated
      def quantize_value(value, skip = [])
        case value
        when Hash
          quantize_statement(value, skip)
        when Array
          quantize_value(value.first, skip)
        else
          PLACEHOLDER
        end
      end

      def quantization_options
        Datadog::Quantization::Hash.merge_options(DEFAULT_OPTIONS, configuration[:quantize])
      end

      def configuration
        Datadog.configuration[:mongo]
      end
    end
  end
end
