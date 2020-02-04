module Datadog
  module Contrib
    module Configuration
      # Resolves a configuration key to a Datadog::Contrib::Configuration:Settings object
      class Resolver
        attr_reader \
          :configurations

        def initialize(&block)
          raise ArgumentError, 'Default configuration block must be provided!' unless block_given?

          @default_configuration_block = block
          @configurations = {}

          add(:default)
        end

        def resolve(key)
          key = :default unless match?(key)
          @configurations[key]
        end

        def add(key, config = nil)
          @configurations[key] = config || new_default_configuration
        end

        def match?(key)
          @configurations.key?(key)
        end

        def new_default_configuration
          @default_configuration_block.call
        end
      end
    end
  end
end
