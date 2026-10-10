# frozen_string_literal: true

module Datadog
  module DI
    # The namespace string under which the DI telemetry metrics are
    # emitted. The emitter files that use the namespace are loaded by
    # direct requires whose chains can skip datadog/di.rb, so the
    # constant lives in this leaf file that every emitter requires.
    TELEMETRY_NAMESPACE = "dynamic_instrumentation"
  end
end
