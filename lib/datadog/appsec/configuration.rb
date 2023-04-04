require_relative 'configuration/settings'

module Datadog
  module AppSec
    # Configuration for AppSec
    # TODO: this is a trivial implementation, check with shareable code with
    # tracer and other products
    module Configuration
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Configuration DSL implementation
      class DSL
        # Struct constant whisker cast for Steep
        Instrument = _ = Struct.new(:name, :options) # rubocop:disable Naming/ConstantName

        def initialize
          @instruments = []
          @options = {}
        end

        attr_reader :instruments, :options

        def instrument(name, options = {})
          @instruments << Instrument.new(name, options)
        end

        def enabled=(value)
          options[:enabled] = value
        end

        def ruleset=(value)
          options[:ruleset] = value
        end

        def ip_denylist=(value)
          options[:ip_denylist] = value
        end

        def user_id_denylist=(value)
          options[:user_id_denylist] = value
        end

        # in microseconds
        def waf_timeout=(value)
          options[:waf_timeout] = value
        end

        def waf_debug=(value)
          options[:waf_debug] = value
        end

        def trace_rate_limit=(value)
          options[:trace_rate_limit] = value
        end

        def obfuscator_key_regex=(value)
          options[:obfuscator_key_regex] = value
        end

        def obfuscator_value_regex=(value)
          options[:obfuscator_value_regex] = value
        end

        def [](key)
          found = @instruments.find { |e| e.name == key }

          found.options if found
        end
      end

      # class-level methods for Configuration
      module ClassMethods
        def configure
          dsl = DSL.new
          yield dsl
          settings.merge(dsl)
          settings
        end

        def settings
          @settings ||= Settings.new
        end
      end
    end
  end
end
