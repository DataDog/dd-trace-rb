require 'ddtrace/configuration/option_set'
require 'ddtrace/configuration/option_definition'
require 'ddtrace/configuration/option_definition_set'

module Datadog
  module Configuration
    # Behavior for a configuration object that has options
    module Options
      def self.included(base)
        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
      end

      # Class behavior for a configuration object with options
      module ClassMethods
        def options
          @options ||= begin
            # Allows for class inheritance of option definitions
            superclass <= Options ? superclass.options.dup : OptionDefinitionSet.new
          end
        end

        protected
        H = {}.freeze
        def option(name, meta = H, &block)
          builder = OptionDefinition::Builder.new(name, meta, &block)
          options[name] = builder.to_definition.tap do
            # Resolve and define helper functions
            # puts "default_helpers(name): #{default_helpers(name).size}"
            # puts "builder.helpers: #{builder.helpers.size}"


            helpers = default_helpers(name)
            helpers = helpers.merge(builder.helpers) unless builder.helpers.empty?

            # helpers = default_helpers(name).merge(builder.helpers)

            define_helpers(helpers)
          end
        end

        private

        CACHE = {}
        def default_helpers(name)
          CACHE[name] ||= begin
                            option_name = name.to_sym

                            {
                              option_name => proc do
                                get_option(option_name)
                              end,
                              "#{name}=" => proc do |value|
                                set_option(option_name, value)
                              end
                            }
                          end
        end

        # def default_helpers(name)
        #   option_name = name.to_sym
        #
        #   {
        #     option_name.to_sym => proc do
        #       get_option(option_name)
        #     end,
        #     "#{option_name}=".to_sym => proc do |value|
        #       set_option(option_name, value)
        #     end
        #   }
        # end


        # Total allocated: 6468727 bytes (47044 objects)
        # Total retained:  918106 bytes (7192 objects)
        #
        # allocated memory by gem
        # -----------------------------------
        # 6447015  dd-trace-rb/lib
        # 21712  other

        # Total allocated: 6525763 bytes (47664 objects)
        # Total retained:  893938 bytes (7020 objects)
        #
        # allocated memory by gem
        # -----------------------------------
        #    6504051  dd-trace-rb/lib
        #      21712  other
        #
        # def default_helpers(name)
        #   option_name = name.to_sym
        #
        #   {
        #     option_name.to_sym => proc do
        #       get_option(option_name)
        #     end,
        #     "#{option_name}=".to_sym => proc do |value|
        #       set_option(option_name, value)
        #     end
        #   }
        # end

        def define_helpers(helpers)
          helpers.each do |name, block|
            next unless block.is_a?(Proc)
            define_method(name, &block)
          end
        end
      end

      # Instance behavior for a configuration object with options
      module InstanceMethods
        def options
          @options ||= OptionSet.new
        end

        def set_option(name, value)
          add_option(name) unless options.key?(name)
          options[name].set(value)
        end

        def get_option(name)
          add_option(name) unless options.key?(name)
          options[name].get
        end

        def reset_option(name)
          assert_valid_option!(name)
          options[name].reset if options.key?(name)
        end

        def option_defined?(name)
          self.class.options.key?(name)
        end

        def options_hash
          self.class.options.merge(options).each_with_object({}) do |(key, _), hash|
            hash[key] = get_option(key)
          end
        end

        def reset_options!
          options.values.each(&:reset)
        end

        private

        def add_option(name)
          assert_valid_option!(name)
          definition = self.class.options[name]
          definition.build(self).tap do |option|
            options[name] = option
          end
        end

        def assert_valid_option!(name)
          unless option_defined?(name)
            raise(InvalidOptionError, "#{self.class.name} doesn't define the option: #{name}")
          end
        end
      end

      InvalidOptionError = Class.new(StandardError)
    end
  end
end
