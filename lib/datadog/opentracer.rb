# typed: strict
require 'opentracing'
require 'opentracing/carrier'
require 'datadog/tracing'

require 'datadog/opentracer/carrier'
require 'datadog/opentracer/tracer'
require 'datadog/opentracer/span'
require 'datadog/opentracer/span_context'
require 'datadog/opentracer/span_context_factory'
require 'datadog/opentracer/scope'
require 'datadog/opentracer/scope_manager'
require 'datadog/opentracer/thread_local_scope'
require 'datadog/opentracer/thread_local_scope_manager'
require 'datadog/opentracer/distributed_headers'
require 'datadog/opentracer/propagator'
require 'datadog/opentracer/text_map_propagator'
require 'datadog/opentracer/binary_propagator'
require 'datadog/opentracer/rack_propagator'
require 'datadog/opentracer/global_tracer'

# Modify the OpenTracing module functions
::OpenTracing.singleton_class.prepend(Datadog::OpenTracer::GlobalTracer)
