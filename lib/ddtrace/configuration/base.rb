require 'ddtrace/environment'
require 'ddtrace/configuration/options'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    module Base
      def self.included(base)
        base.send(:extend, Datadog::Environment::Helpers)
        base.send(:include, Options)
      end

      def initialize(options = {})
        configure(options)
      end

      def configure(opts = {})
        # Sort the options in preference of dependency order first
        ordering = self.class.options.dependency_order
        sorted_opts = opts.sort_by do |name, _value|
          ordering.index(name) || (ordering.length + 1)
        end

        # Ruby 2.0 doesn't support Array#to_h
        sorted_opts = Hash[*sorted_opts.flatten]

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

      def reset!
        reset_options!
      end
    end
  end
end
