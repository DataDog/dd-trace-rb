require 'ddtrace/registry'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  @tracer = Tracer.new
  @registry = Registry.new

  # Default tracer that can be used as soon as +ddtrace+ is required:
  #
  #   require 'ddtrace'
  #
  #   span = Datadog.tracer.trace('web.request')
  #   span.finish()
  #
  # If you want to override the default tracer, the recommended way
  # is to "pin" your own tracer onto your traced component:
  #
  #   tracer = Datadog::Tracer.new
  #   pin = Datadog::Pin.get_from(mypatchcomponent)
  #   pin.tracer = tracer

  def self.tracer
    @tracer
  end

  def self.registry
    @registry
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Configuration)
        yield(target)
      else
        Configuration::PinSetup.new(target, opts).call
      end
    end
  end
end

# Monkey currently is responsible for loading all contributions, which in turn
# rely on the registry defined above. We should make our code less dependent on
# the load order, by letting things be lazily loaded while keeping
# thread-safety.
require 'ddtrace/monkey'
