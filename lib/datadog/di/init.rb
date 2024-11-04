# frozen_string_literal: true

# Require 'datadog/di/init' early in the application boot process to
# enable dynamic instrumentation for third-party libraries used by the
# application.

require_relative '../tracing'
require_relative '../tracing/contrib'
require_relative '../di'

Datadog::DI.activate_tracking!
