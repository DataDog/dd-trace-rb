# typed: strict
# Entrypoint file for auto instrumentation.
#
# This file's path is part of the @public_api.
require 'ddtrace'

Datadog.add_auto_instrument
Datadog.profiler.start if Datadog.profiler
