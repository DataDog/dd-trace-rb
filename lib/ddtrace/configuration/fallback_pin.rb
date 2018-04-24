require 'ddtrace/pin'

module Datadog
  class Configuration
    # A Pin that acts as a delegate to a list of other pins
    # If the value on one pin is nil, it tries the next one.
    class FallbackPin < Pin
      OPTIONS = [
        :service_name,
        :app,
        :tags,
        :app_type,
        :name,
        :tracer,
        :config
      ].freeze

      def initialize(*pins)
        @pins = pins.compact
      end

      # Define accessor methods that delegate to pins
      OPTIONS.each do |option|
        define_method(option) do
          @pins.find do |pin|
            value = pin.send(option)
            return value unless value.nil?
          end
        end

        define_method("#{option}=") do |value|
          return nil if @pins.empty?
          @pins.first.send("#{option}=", value)
        end
      end

      def enabled?
        return tracer.enabled if tracer
        false
      end

      alias service= service_name=
      alias service service_name

      def to_s
        "FallbackPin(#{@pins})"
      end
    end
  end
end
