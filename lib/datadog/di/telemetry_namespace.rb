# frozen_string_literal: true

# Defined in this leaf file rather than datadog/di.rb (the module's home)
# because the emitter files that reference it are loaded by direct requires
# whose chains never reach datadog/di.rb. One definition keeps the literal
# from drifting between emitters.

module Datadog
  module DI
    TELEMETRY_NAMESPACE = "dynamic_instrumentation"
  end
end
