module Datadog
  module Configuration
    # PinSetup translates a flat hash into a Pin configuration
    # This class should be removed if we ever remove/refactor the Pin class
    class PinSetup
      def initialize(target, opts = {})
        @pin = Pin.get_from(target)
        @opts = opts
      end

      def call
        return unless pin

        ATTRS.each { |key| pin.public_send("#{key}=", opts[key]) if opts[key] }

        pin.config = opts.reject { |key, _| ATTRS.include?(key) }

        true
      end

      private

      attr_reader :pin, :opts

      ATTRS = [:app, :tags, :app_type, :name, :tracer, :service_name].freeze

      private_constant :ATTRS
    end
  end
end
