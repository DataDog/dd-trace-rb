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

    attr_reader :service_name
    attr_accessor :app
    attr_accessor :tags
    attr_accessor :app_type
    attr_accessor :name
    attr_accessor :tracer
    attr_accessor :config

    def initialize(service_name, options = {})
      @app = options[:app]
      @tags = options[:tags]
      @app_type = options[:app_type]
      @name = nil # this would rarely be overriden as it's really span-specific
      @tracer = options[:tracer] || Datadog.tracer
      @config = options[:config]
      self.service_name = service_name
    end

    def enabled?
      return @tracer.enabled if @tracer
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

    def service_name=(name)
      @service_name = name
    end

    alias service= service_name=
    alias service service_name

    def to_s
      "Pin(service:#{service},app:#{app},app_type:#{app_type},name:#{name})"
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
        Datadog::Logger.log.warn("#{method_name}:#{DEPRECATION_WARNING}")
      end
    end
  end
end
