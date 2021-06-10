require 'ddtrace'

Datadog.add_auto_instrument
Datadog.profiler.start if Datadog.profiler
