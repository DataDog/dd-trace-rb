# typed: false

module Datadog
  # A {Datadog::Pin} sets metadata on a particular object.
  # This is useful if you wanted to, say, trace two different
  # database clusters.
  class Pin
    SETTER_METHOD = '='.freeze
    OPTIONS_SEPARATOR = ', '.freeze

    def self.get_from(obj)
      return nil unless obj.respond_to? :datadog_pin

      obj.datadog_pin
    end

    def self.set_on(obj, **options)
      if (pin = get_from(obj))
        options.each { |k, v| pin[k] = v }
      else
        pin = new(**options)
        pin.onto(obj)
      end

      pin
    end

    attr_accessor :options

    def initialize(**options)
      @options = options
    end

    def [](name)
      @options[name]
    end

    def []=(name, value)
      @options[name] = value
    end

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
    # rubocop:enable Style/TrivialAccessors

    def to_s
      pretty_options = options.to_a.map { |k, v| "#{k}:#{v}" }.join(OPTIONS_SEPARATOR)
      "Pin(#{pretty_options})"
    end
  end
end
