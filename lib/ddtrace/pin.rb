require 'ddtrace/patcher'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Pin (a.k.a Patch INfo) is a small class which is used to
  # set tracing metadata on a particular traced object.
  # This is useful if you wanted to, say, trace two different
  # database clusters.
  class Pin
    def self.get_from(obj)
      return nil unless obj.respond_to? :datadog_pin
      obj.datadog_pin
    end

    attr_accessor :app
    attr_accessor :app_type
    attr_accessor :config
    attr_accessor :name
    attr_accessor :service_name
    attr_accessor :tags
    attr_reader :tracer
    attr_accessor :writer

    alias service= service_name=
    alias service service_name

    def initialize(service_name, options = {})
      deprecation_warning unless options[:tracer].is_a?(Proc) || options[:tracer].nil?

      @app = options[:app]
      @app_type = options[:app_type]
      @config = options[:config]
      @name = nil # this would rarely be overriden as it's really span-specific
      @service_name = service_name
      @tags = options[:tags]
      @tracer = options[:tracer]
    end

    def tracer
      @tracer.is_a?(Proc) ? @tracer.call : (@tracer || Datadog.tracer)
    end

    def enabled?
      return tracer.enabled if tracer
      false
    end

    # rubocop:disable Style/TrivialAccessors
    def onto(obj)
      unless obj.respond_to? :datadog_pin=
        obj.instance_exec do
          def datadog_pin=(pin)
            @datadog_pin = pin
          end
        end
      end

      unless obj.respond_to? :datadog_pin
        obj.instance_exec do
          def datadog_pin
            @datadog_pin
          end
        end
      end

      obj.datadog_pin = self
    end

    def to_s
      "Pin(service:#{service},app:#{app},app_type:#{app_type},name:#{name})"
    end

    private

    DEPRECATION_WARNING = %(
      Explicitly providing a tracer instance is DEPRECATED.
      It's recommended to not provide an explicit tracer instance
      and let Datadog::Pin resolve the correct tracer internally.
      ).freeze

    def deprecation_warning
      log_deprecation_warning('Datadog::Pin.new')
    end

    include Datadog::Patcher

    def log_deprecation_warning(method_name)
      # Only log each deprecation warning once (safeguard against log spam)
      do_once(method_name) do
        Datadog.logger.warn("#{method_name}:#{DEPRECATION_WARNING}")
      end
    end
  end

  # Modification to Pin which logs deprecation warnings if accessed.
  # Will be used by integrations which are phasing out the direct use of #datadog_pin.
  module DeprecatedPin
    include Datadog::Patcher

    DEPRECATION_WARNING = %(
      Use of Datadog::Pin is DEPRECATED.
      Upgrade to the configuration API using the migration guide here:
      https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0).freeze

    # Raise a deprecation warning when #datadog_pin or #datadog_pin= is accessed.
    def onto(obj)
      obj.instance_exec(self) do |pin|
        @datadog_deprecated_pin = pin

        unless respond_to? :datadog_pin=
          def datadog_pin=(pin)
            @datadog_deprecated_pin.log_deprecation_warning('#datadog_pin=')
            @datadog_pin = pin
          end
        end

        unless respond_to? :datadog_pin
          def datadog_pin
            @datadog_deprecated_pin.log_deprecation_warning('#datadog_pin')
            @datadog_pin
          end
        end

        # Set instance variable to avoid deprecation warnings
        @datadog_pin = @datadog_deprecated_pin
      end

      self
    end

    def log_deprecation_warning(method_name)
      # Only log each deprecation warning once (safeguard against log spam)
      do_once(method_name) do
        Datadog.logger.warn("#{method_name}:#{DEPRECATION_WARNING}")
      end
    end
  end
end
