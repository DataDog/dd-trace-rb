module Datadog
  # Namespace for ddtrace OpenTracing implementation
  module OpenTracing
    module_function

    def supported?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0')
    end

    def load_opentracing
      require 'opentracing'
      require 'opentracing/carrier'
      require 'ddtrace/opentracing/tracer'
      require 'ddtrace/opentracing/span'
      require 'ddtrace/opentracing/span_context'
    end

    load_opentracing if supported?
  end
end
