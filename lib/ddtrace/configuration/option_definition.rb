module Datadog
  module Configuration
    # Represents a definition for an integration configuration option
    class OptionDefinition
      IDENTITY = ->(x) { x }

      attr_reader \
        :default,
        :depends_on,
        :lazy,
        :name,
        :setter

      def initialize(name, meta = {}, &block)
        @default = meta[:default]
        @depends_on = meta[:depends_on] || []
        @lazy = meta[:lazy] || false
        @name = name.to_sym
        @setter = meta[:setter] || block || IDENTITY
      end

      def default_value
        lazy ? @default.call : @default
      end

      # Acts as DSL for building OptionDefinitions
      class Builder
        attr_reader \
          :helpers

        def initialize(name, options = {})
          @default = nil
          @depends_on = []
          @helpers = {}
          @lazy = false
          @name = name.to_sym
          @setter = OptionDefinition::IDENTITY

          # If options were supplied, apply them.
          apply_options!(options)

          # Apply block if given.
          yield(self) if block_given?
        end

        def depends_on(*values)
          @depends_on = values.flatten
        end

        def default(value = nil, &block)
          @default = block_given? ? block : value
        end

        # rubocop:disable Style/TrivialAccessors
        # (Rubocop erroneously thinks #lazy == #lazy= )
        def lazy(value)
          @lazy = value
        end

        def setter(&block)
          @setter = block
        end

        def helper(name, *_args, &block)
          @helpers[name] = block
        end

        # For applying options for OptionDefinition
        def apply_options!(options = {})
          return if options.nil? || options.empty?

          default(options[:default]) if options.key?(:default)
          depends_on(*options[:depends_on]) if options.key?(:depends_on)
          lazy(options[:lazy]) if options.key?(:lazy)
          setter(&options[:setter]) if options.key?(:setter)
        end

        def to_definition
          OptionDefinition.new(@name, meta)
        end

        def meta
          {
            default: @default,
            depends_on: @depends_on,
            lazy: @lazy,
            setter: @setter
          }
        end
      end
    end
  end
end
