require 'ddtrace/pin'

module Datadog
  class Configuration
    # A Pin that acts as a delegate to configuration Proxy
    class ProxyPin < Pin
      OPTIONS = [
        :service_name,
        :app,
        :tags,
        :app_type,
        :name,
        :tracer,
        :config
      ].freeze

      def initialize(proxy)
        @proxy = proxy
      end

      # Define accessor methods that delegate to the Proxy
      OPTIONS.each do |option|
        define_method(option) do
          @proxy.option?(option) ? @proxy[option] : super()
        end

        define_method("#{option}=") do |value|
          if @proxy.option?(option)
            @proxy[option] = value
          else
            super(value)
          end
        end
      end

      def enabled?
        return tracer.enabled if tracer
        false
      end

      alias service= service_name=
      alias service service_name

      def to_s
        "ProxyPin(#{@proxy})"
      end
    end
  end
end
