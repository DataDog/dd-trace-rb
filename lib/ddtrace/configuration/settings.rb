require 'ddtrace/configuration/options'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    class Settings
      include Options

      option :tracer, default: Tracer.new

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

      # Backwards compatibility for configuring tracer e.g. `c.tracer debug: true`
      def tracer(options = nil)
        tracer = options && options.key?(:instance) ? set_option(:tracer, options[:instance]) : get_option(:tracer)

        tracer.tap do |t|
          unless options.nil?
            t.configure(options)
            t.class.log = options[:log] if options[:log]
            t.set_tags(options[:tags]) if options[:tags]
            t.set_tags(env: options[:env]) if options[:env]
            t.class.debug_logging = options.fetch(:debug, false)
          end
        end
      end

      class << self
        protected

        def env_to_bool(var, default = nil)
          ENV.key?(var) ? ENV[var].to_s.downcase == 'true' : default
        end

        def env_to_float(var, default = nil)
          ENV.key?(var) ? ENV[var].to_f : default
        end
      end
    end
  end
end
