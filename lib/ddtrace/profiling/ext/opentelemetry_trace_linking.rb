module Datadog
  module Profiling
    module Ext
      # Provides an OpenTelemetry-compliant SpanProcessor that enables OpenTelemetry traces to be linked with profiles.
      #
      # DEVELOPMENT NOTES:
      # * Unlike most of the rest of the Profiler, this class is directly referenced in the docs and is
      # expected to be instantiated by library users.
      # * It MUST have no dependency on the rest of Profiler, so that it can be safely used even when Profiler is
      # disabled or not available.
      # * It MUST not rely on OpenTelemetry being available at all **prior to being instanced**. E.g. this class
      # can be loaded even if none of the OpenTelemetry gems are available.
      # * The expected API is documented at
      # <https://github.com/open-telemetry/opentelemetry-specification/blob/0cb45c779a0b8a78d669aaf61c1b39ffab7dc0ae/specification/trace/sdk.md#interface-definition>
      # and
      # <https://github.com/open-telemetry/opentelemetry-ruby/blob/bef61b5ae4493f5ac8a3da7d843a5ff79f15f715/sdk/lib/opentelemetry/sdk/trace/span_processor.rb>
      class OpenTelemetryTraceLinking
        # https://github.com/open-telemetry/opentelemetry-ruby/blob/bef61b5ae4493f5ac8a3da7d843a5ff79f15f715/sdk/lib/opentelemetry/sdk/trace/export.rb#L16
        SUCCESS = 0
        private_constant :SUCCESS

        def on_start(span, _parent_context)
          span.set_attribute(Datadog::Ext::Runtime::TAG_ID, Datadog::Runtime::Identity.id)
        end

        def on_finish(*_)
          # Nothing to do
        end

        def force_flush(**_)
          SUCCESS
        end

        def shutdown(**_)
          SUCCESS
        end
      end
    end
  end
end
