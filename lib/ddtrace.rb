require 'thread'

require 'ddtrace/registry'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'
require 'ddtrace/patcher'

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

require 'ddtrace/contrib/base'
require 'ddtrace/contrib/rack/patcher'
require 'ddtrace/contrib/rails/patcher'
require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/elasticsearch/patcher'
require 'ddtrace/contrib/faraday/patcher'
require 'ddtrace/contrib/grape/patcher'
require 'ddtrace/contrib/redis/patcher'
require 'ddtrace/contrib/http/patcher'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/contrib/sucker_punch/patcher'
require 'ddtrace/contrib/mongodb/patcher'
require 'ddtrace/contrib/dalli/patcher'
require 'ddtrace/contrib/resque/patcher'
require 'ddtrace/contrib/racecar/patcher'
require 'ddtrace/contrib/sidekiq/patcher'
require 'ddtrace/monkey'
