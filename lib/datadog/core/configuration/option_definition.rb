# frozen_string_literal: true

require_relative 'option'

module Datadog
  module Core
    module Configuration
      # Represents a definition for an integration configuration option
      class OptionDefinition
        IDENTITY = ->(new_value, _old_value) { new_value }

        attr_reader \
          :parent,
          :default,
          :default_proc,
          :env,
          :env_parser,
          :name,
          :after_set,
          :resetter,
          :setter,
          :type,
          :type_options

        def initialize(name, option_attributes, &block)
          @parent = option_attributes[:parent]

          @default = option_attributes[:default]
          @default_proc = option_attributes[:default_proc]
          @env = option_attributes[:env]
          @env_parser = option_attributes[:env_parser]
          @name = name.to_sym
          @after_set = option_attributes[:after_set]
          @resetter = option_attributes[:resetter]
          @setter = option_attributes[:setter] || block || IDENTITY
          @type = option_attributes[:type]
          @type_options = option_attributes[:type_options]
        end

        # Creates a new Option, bound to the context provided.
        def build(context)
          Option.new(self, context)
        end

        # Acts as DSL for building OptionDefinitions
        # @public_api
        class Builder
          # Steep: https://github.com/soutaro/steep/issues/1880
          InvalidOptionError = Class.new(StandardError) # steep:ignore IncompatibleAssignment

          attr_reader \
            :helpers

          def initialize(name, options = {})
            @parent = options[:parent]

            @env = nil
            @env_parser = nil
            @default = nil
            @default_proc = nil
            @helpers = {}
            @name = name.to_sym
            @after_set = nil
            @resetter = nil
            @setter = OptionDefinition::IDENTITY
            @type = nil
            @type_options = {}
            # If options were supplied, apply them.
            apply_options!(options)

            # Apply block if given.
            yield(self) if block_given?

            validate_options!
          end

          def env(value) # standard:disable Style/TrivialAccessors
            @env = value
          end

          # Invoked when the option is first read, and {#env} is defined.
          # The block provided is only invoked if the environment variable is present (not-nil).
          def env_parser(&block)
            @env_parser = block
          end

          def default(value = nil, &block)
            @default = block || value
          end

          def default_proc(&block)
            @default_proc = block
          end

          def helper(name, *_args, &block)
            @helpers[name] = block
          end

          def after_set(&block)
            @after_set = block
          end

          def resetter(&block)
            @resetter = block
          end

          def setter(&block)
            @setter = block
          end

          def type(value, nilable: false)
            @type = value
            @type_options = {nilable: nilable}

            value
          end

          # For applying options for OptionDefinition
          def apply_options!(options = {})
            return if options.nil? || options.empty?

            default(options[:default]) if options.key?(:default)
            default_proc(&options[:default_proc]) if options.key?(:default_proc)
            env(options[:env]) if options.key?(:env)
            env_parser(&options[:env_parser]) if options.key?(:env_parser)
            after_set(&options[:after_set]) if options.key?(:after_set)
            resetter(&options[:resetter]) if options.key?(:resetter)
            # Steep: https://github.com/soutaro/steep/issues/1979
            setter(&options[:setter]) if options.key?(:setter) # steep:ignore BlockTypeMismatch
            type(options[:type], **(options[:type_options] || {})) if options.key?(:type)
          end

          def to_definition
            # Steep: https://github.com/soutaro/steep/issues/2122
            OptionDefinition.new(@name, parent: @parent, **option_attributes) # steep:ignore ArgumentTypeMismatch
          end

          def option_attributes
            {
              default: @default,
              default_proc: @default_proc,
              env: @env,
              env_parser: @env_parser,
              after_set: @after_set,
              resetter: @resetter,
              setter: @setter,
              type: @type,
              type_options: @type_options
            }
          end

          private

          def validate_options!
            if !@default.nil? && @default_proc
              raise InvalidOptionError,
                'Using `default` and `default_proc` is not allowed. Please use one or the other.' \
                                'If you want to store a block as the default value use `default_proc`' \
                                ' otherwise use `default`'
            end
          end
        end
      end
    end
  end
end
