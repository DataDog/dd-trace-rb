require 'ddtrace/configuration/option'

module Datadog
  module Configuration
    # Represents a definition for an integration configuration option
    class OptionDefinition
      IDENTITY = ->(x) { x }

      attr_reader \
        :default,
        :delegate_to,
        :depends_on,
        :lazy,
        :name,
        :on_set,
        :resetter,
        :setter

      def initialize(name, meta = {}, &block)
        @default = meta[:default]
        @delegate_to = meta[:delegate_to]
        @depends_on = meta[:depends_on] || []
        @lazy = meta[:lazy] || false
        @name = name.to_sym
        @on_set = meta[:on_set]
        @resetter = meta[:resetter]
        @setter = meta[:setter] || block || IDENTITY
      end

      def default_value
        lazy ? @default.call : @default
      end

      # Creates a new Option, bound to the context provided.
      def build(context)
        Option.new(self, context)
      end

      # Acts as DSL for building OptionDefinitions
      class Builder
        attr_reader \
          :helpers

        def initialize(name, options = {})
          @default = nil
          @delegate_to = nil
          @depends_on = []
          @helpers = {}
          @lazy = false
          @name = name.to_sym
          @on_set = nil
          @resetter = nil
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

        def delegate_to(&block)
          @delegate_to = block
        end

        def helper(name, *_args, &block)
          @helpers[name] = block
        end

        # rubocop:disable Style/TrivialAccessors
        # (Rubocop erroneously thinks #lazy == #lazy= )
        def lazy(value = true)
          @lazy = value
        end

        def on_set(&block)
          @on_set = block
        end

        def resetter(&block)
          @resetter = block
        end

        def setter(&block)
          @setter = block
        end

        # For applying options for OptionDefinition
        def apply_options!(options = {})
          return if options.nil? || options.empty?

          default(options[:default]) if options.key?(:default)
          delegate_to(&options[:delegate_to]) if options.key?(:delegate_to)
          depends_on(*options[:depends_on]) if options.key?(:depends_on)
          lazy(options[:lazy]) if options.key?(:lazy)
          on_set(&options[:on_set]) if options.key?(:on_set)
          resetter(&options[:resetter]) if options.key?(:resetter)
          setter(&options[:setter]) if options.key?(:setter)
        end

        def to_definition
          OptionDefinition.new(@name, meta)
        end

        def meta
          {
            default: @default,
            delegate_to: @delegate_to,
            depends_on: @depends_on,
            lazy: @lazy,
            on_set: @on_set,
            resetter: @resetter,
            setter: @setter
          }
        end
      end
    end
  end
end
