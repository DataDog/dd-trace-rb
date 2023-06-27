# frozen_string_literal: true

require_relative 'option'

module Datadog
  module Core
    module Configuration
      # Represents a definition for an integration configuration option
      class OptionDefinition
        IDENTITY = ->(new_value, _old_value) { new_value }

        attr_reader \
          :default,
          :default_proc,
          :delegate_to,
          :depends_on,
          :name,
          :on_set,
          :resetter,
          :setter,
          :type

        def initialize(name, meta = {}, &block)
          @default = meta[:default]
          @default_proc = meta[:default_proc]
          @delegate_to = meta[:delegate_to]
          @depends_on = meta[:depends_on] || []
          @name = name.to_sym
          @on_set = meta[:on_set]
          @resetter = meta[:resetter]
          @setter = meta[:setter] || block || IDENTITY
          @type = meta[:type]
        end

        # Creates a new Option, bound to the context provided.
        def build(context)
          Option.new(self, context)
        end

        # Acts as DSL for building OptionDefinitions
        # @public_api
        class Builder
          class InvalidOptionError < StandardError; end

          attr_reader \
            :helpers

          def initialize(name, options = {})
            @default = nil
            @default_proc = nil
            @delegate_to = nil
            @depends_on = []
            @helpers = {}
            @name = name.to_sym
            @on_set = nil
            @resetter = nil
            @setter = OptionDefinition::IDENTITY
            @type = nil

            # If options were supplied, apply them.
            apply_options!(options)

            # Apply block if given.
            yield(self) if block_given?

            validate_options!
          end

          def depends_on(*values)
            @depends_on = values.flatten
          end

          def default(value = nil, &block)
            @default = block || value
          end

          def default_proc(&block)
            @default_proc = block
          end

          def delegate_to(&block)
            @delegate_to = block
          end

          def helper(name, *_args, &block)
            @helpers[name] = block
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

          def type(value = nil)
            @type = value
          end

          # For applying options for OptionDefinition
          def apply_options!(options = {})
            return if options.nil? || options.empty?

            default(options[:default]) if options.key?(:default)
            default_proc(&options[:default_proc]) if options.key?(:default_proc)
            delegate_to(&options[:delegate_to]) if options.key?(:delegate_to)
            depends_on(*options[:depends_on]) if options.key?(:depends_on)
            on_set(&options[:on_set]) if options.key?(:on_set)
            resetter(&options[:resetter]) if options.key?(:resetter)
            setter(&options[:setter]) if options.key?(:setter)
            type(&options[:type]) if options.key?(:type)
          end

          def to_definition
            OptionDefinition.new(@name, meta)
          end

          def meta
            {
              default: @default,
              default_proc: @default_proc,
              delegate_to: @delegate_to,
              depends_on: @depends_on,
              on_set: @on_set,
              resetter: @resetter,
              setter: @setter,
              type: @type
            }
          end

          private

          def validate_options!
            if !@default.nil? && @default_proc
              raise InvalidOptionError,
                'Using `default` and `default_proc` is not allowed. Please use one or the other.' \
                                'If you want to store a block as the default value use `default_proc`'\
                                ' otherwise use `default`'
            end
          end
        end
      end
    end
  end
end
