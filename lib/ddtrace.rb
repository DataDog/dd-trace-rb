require 'thread'

require 'ddtrace/registry'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/quantization/hash'
require 'ddtrace/quantization/http'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'
require 'ddtrace/patcher'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  @tracer = Tracer.new
  @registry = Registry.new
  @configuration = Configuration.new(registry: @registry)

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
  class << self
    attr_reader :tracer, :registry
    attr_accessor :configuration

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
require 'ddtrace/contrib/active_model_serializers/patcher'
require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/aws/integration'
require 'ddtrace/contrib/concurrent_ruby/integration'
require 'ddtrace/contrib/dalli/integration'
require 'ddtrace/contrib/delayed_job/integration'
require 'ddtrace/contrib/elasticsearch/integration'
require 'ddtrace/contrib/excon/patcher'
require 'ddtrace/contrib/faraday/patcher'
require 'ddtrace/contrib/grape/patcher'
require 'ddtrace/contrib/graphql/patcher'
require 'ddtrace/contrib/grpc/patcher'
require 'ddtrace/contrib/http/integration'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/mongodb/patcher'
require 'ddtrace/contrib/mysql2/integration'
require 'ddtrace/contrib/racecar/integration'
require 'ddtrace/contrib/rack/integration'
require 'ddtrace/contrib/rails/integration'
require 'ddtrace/contrib/rake/integration'
require 'ddtrace/contrib/redis/integration'
require 'ddtrace/contrib/resque/integration'
require 'ddtrace/contrib/rest_client/integration'
require 'ddtrace/contrib/sequel/integration'
require 'ddtrace/contrib/sidekiq/integration'
require 'ddtrace/contrib/sucker_punch/integration'
require 'ddtrace/monkey'
