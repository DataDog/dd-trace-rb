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

    attr_accessor :service
    attr_accessor :app
    attr_accessor :tags
    attr_accessor :app_type
    attr_accessor :name
    attr_accessor :tracer
    attr_accessor :config

    # [ruby19] named parameters would be more idiomatic here, but would break backward compatibility
    def initialize(service, options = { app: nil, tags: nil, app_type: nil, tracer: nil, config: nil })
      @service = service
      @app = options.fetch(:app, nil)
      @tags = options.fetch(:tags, nil)
      @app_type = options.fetch(:app_type, nil)
      @name = nil # this would rarely be overriden as it's really span-specific
      @tracer = options[:tracer] || Datadog.tracer
      @config = options.fetch(:config, nil)
    end

    def enabled?
      return @tracer.enabled if @tracer
      false
    end

    def onto(obj)
      unless obj.respond_to? :datadog_pin=
        obj.instance_exec do
          def datadog_pin=(pin)
            Datadog::Tracer.log.debug("Set pin #{pin.service} on #{self.class}.")
            @datadog_pin = pin
          end
        end
      end

      unless obj.respond_to? :datadog_pin
        obj.instance_exec do
          def datadog_pin
            Datadog::Tracer.log.debug("Get pin from #{self.class}.")
            @datadog_pin
          end
        end
      end

      obj.datadog_pin = self
    end

    def to_s
      "Pin(service:#{@service},app:#{@app},app_type:#{@app_type},name:#{@name})"
    end
  end
end
