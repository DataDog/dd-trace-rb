# During development, we load `ddtrace` by through `ddtrace.gemspec`,
# which in turn eager loads 'ddtrace/version'.
#
# Users load this gem by requiring this file.
# We need to ensure that any files loaded in our gemspec are also loaded here.
require 'ddtrace/version'

require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/quantization/hash'
require 'ddtrace/quantization/http'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'
require 'ddtrace/patcher'
require 'ddtrace/metrics'
require 'ddtrace/auto_instrument_base'
require 'ddtrace/profiling'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  extend Configuration
  extend AutoInstrumentBase

  # Load built-in Datadog integrations
  require 'ddtrace/contrib'

  # Load extension to global Datadog objects
  require 'ddtrace/contrib/extensions'
  extend(Contrib::Extensions)
  Configuration::Settings.include(Contrib::Extensions::Configuration::Settings)

  # Load Contrib auto instrumentation
  require 'ddtrace/contrib/auto_instrument'
  extend(Contrib::AutoInstrument)

  # Load and extend OpenTelemetry compatibility by default
  require 'ddtrace/opentelemetry/extensions'
  extend OpenTelemetry::Extensions

  # Add shutdown hook:
  # Ensures the tracer has an opportunity to flush traces
  # and cleanup before terminating the process.
  at_exit { Datadog.shutdown! }
end
