module Datadog
  # Namespace for ddtrace OpenTracing implementation
  module OpenTracer
    module_function

    def supported?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0')
    end

    def load_opentracer
      require 'opentracing'
      require 'opentracing/carrier'
      require 'ddtrace'
      require 'ddtrace/opentracer/carrier'
      require 'ddtrace/opentracer/tracer'
      require 'ddtrace/opentracer/span'
      require 'ddtrace/opentracer/span_context'
      require 'ddtrace/opentracer/scope'
      require 'ddtrace/opentracer/scope_manager'
      require 'ddtrace/opentracer/global_tracer'

      # Modify the OpenTracing module functions
      OpenTracing.module_eval do
        class << self
          prepend Datadog::OpenTracer::GlobalTracer
        end
      end
    end

    load_opentracer if supported?
  end
end
