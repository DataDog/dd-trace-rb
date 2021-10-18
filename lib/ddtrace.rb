# typed: strict
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
require 'datadog/security/autoload'

require 'datadog/contrib'
require 'ddtrace/contrib/auto_instrument'
require 'ddtrace/contrib/extensions'

require 'ddtrace/opentelemetry/extensions'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  extend Configuration
  extend AutoInstrumentBase

  # Load built-in Datadog integrations
  extend Contrib::Extensions
  # Load Contrib auto instrumentation
  extend Contrib::AutoInstrument
  # Load Contrib extension to global Datadog objects
  Configuration::Settings.include Contrib::Extensions::Configuration::Settings

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions

  # Add shutdown hook:
  # Ensures the tracer has an opportunity to flush traces
  # and cleanup before terminating the process.
  at_exit do
    if Interrupt === $! # rubocop:disable Style/SpecialGlobalVars is process terminating due to a ctrl+c or similar?
      Datadog.send(:handle_interrupt_shutdown!)
    else
      Datadog.shutdown!
    end
  end
end
