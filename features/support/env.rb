# Declare any lifecycle hooks in this file: https://cucumber.io/docs/cucumber/api/#hooks
# This file is loaded for every scenario.

# Load our library
require 'ddtrace'

# Ensure there's an active trace when running scenarios
Before do
  @trace = Datadog::Tracing.send(:tracer).send(:start_trace)
end
