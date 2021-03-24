require 'ddtrace/patcher'
require 'ddtrace/utils/only_once'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Pin (a.k.a Patch INfo) is a small class which is used to
  # set tracing metadata on a particular traced object.
  # This is useful if you wanted to, say, trace two different
  # database clusters.
  class Pin
    DEPRECATION_WARN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

    def self.get_from(obj)
      return nil unless obj.respond_to? :datadog_pin

      obj.datadog_pin
    end

    attr_accessor :app, :app_type, :config, :name, :service_name, :tags, :writer

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
      DEPRECATION_WARN_ONLY_ONCE.run do
        Datadog.logger.warn("Datadog::Pin.new:#{DEPRECATION_WARNING}")
      end
    end
  end
end
