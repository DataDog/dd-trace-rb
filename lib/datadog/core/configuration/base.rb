require_relative '../environment/variable_helpers'
require_relative 'options'

module Datadog
  module Core
    module Configuration
      # Basic configuration behavior
      # @public_api
      module Base
        def self.included(base)
          base.extend(Core::Environment::VariableHelpers)
          base.include(Core::Environment::VariableHelpers)
          base.include(Options)

          base.extend(ClassMethods)
          base.include(InstanceMethods)
        end

        # Class methods for configuration
        # @public_api
        module ClassMethods
          protected

          # Allows subgroupings of settings to be defined.
          # e.g. `settings :foo { option :bar }` --> `config.foo.bar`
          # @param [Symbol] name option name. Methods will be created based on this name.
          def settings(name, &block)
            settings_class = new_settings_class(&block)

            option(name) do |o|
              o.default { settings_class.new }
              o.lazy

              o.resetter do |value|
                value.reset! if value.respond_to?(:reset!)
                value
              end

              o.type settings_class
            end
          end

          private

          def new_settings_class(&block)
            Class.new { include Configuration::Base }.tap do |klass|
              klass.instance_eval(&block) if block
            end
          end
        end

        # Instance methods for configuration
        # @public_api
        module InstanceMethods
          def initialize(options = {})
            configure(options) unless options.empty?
          end

          def configure(opts = {})
            # Sort the options in preference of dependency order first
            ordering = self.class.options.dependency_order
            sorted_opts = opts.sort_by do |name, _value|
              ordering.index(name) || (ordering.length + 1)
            end.to_h

            # Apply options in sort order
            sorted_opts.each do |name, value|
              if respond_to?("#{name}=")
                send("#{name}=", value)
              elsif option_defined?(name)
                set_option(name, value)
              end
            end

            # Apply any additional settings from block
            yield(self) if block_given?
          end

          def to_h
            options_hash
          end

          # Retrieves a nested option from a list of symbols
          def dig(*options)
            raise ArgumentError, 'expected at least one option' if options.empty?

            options.inject(self) do |receiver, option|
              receiver.send(option)
            end
          end

          def reset!
            reset_options!
          end
        end
      end
    end
  end
end
