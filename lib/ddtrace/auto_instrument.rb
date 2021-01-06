require 'ddtrace'

Datadog.add_auto_instrument if Datadog.respond_to?(:add_auto_instrument)
