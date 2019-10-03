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

      def configure(options = {})
        self.class.options.dependency_order.each do |name|
          next unless options.key?(name)
          respond_to?("#{name}=") ? send("#{name}=", options[name]) : set_option(name, options[name])
        end

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
