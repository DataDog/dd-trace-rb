# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Hooks
      # EVP flagevaluation hook — structural copy of FlagEvalHook for the new EVP path.
      #
      # This hook does ONLY cheap capture + non-blocking enqueue on the caller's eval thread.
      # All aggregation (canonical key, tier routing, cap enforcement) is performed
      # in the background by the FlagEvaluation::Writer.
      #
      # OTel non-regression: hooks/flag_eval_hook.rb and metrics/flag_eval_metrics.rb
      # are byte-for-byte untouched. This hook is wired ALONGSIDE the existing OTel hook.
      class FlagEvalEVPHook
        # Include the Hook module if available (SDK >= 0.5.0) for interface documentation
        # and default implementations of other hook methods (before, after, error)
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        # Returns true if the OpenFeature SDK supports hooks (>= 0.5.0)
        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
        end

        def initialize(writer)
          @writer = writer
        end

        # finally covers success, error, AND default paths (not just After).
        # Cheap extraction only — no aggregation on the caller thread.
        def finally(hook_context:, evaluation_details:, **_opts)
          writer = @writer
          return unless writer

          # Eval-time stamped by the provider at eval-entry time; fall back to hook-fire time.
          # Metadata key: 'dd.eval.timestamp_ms' (int, ms since epoch) — stamped at eval entry.
          metadata = evaluation_details.flag_metadata
          eval_time_ms = metadata.is_a?(Hash) ? metadata['dd.eval.timestamp_ms'] : nil
          eval_time_ms ||= (Core::Utils::Time.now.to_f * 1000).to_i

          writer.enqueue(
            flag_key: hook_context.flag_key,
            variant: evaluation_details.variant, # nil = absent = runtime default
            reason: evaluation_details.reason.to_s,
            allocation_key: extract_allocation_key(evaluation_details),
            targeting_key: hook_context.evaluation_context&.targeting_key,
            eval_time_ms: eval_time_ms,
            attrs: hook_context.evaluation_context&.attributes || {},
          )
        end

        private

        # Same key as OTel hook ('__dd_allocation_key') — do not diverge.
        def extract_allocation_key(evaluation_details)
          metadata = evaluation_details.flag_metadata
          return unless metadata.is_a?(Hash)

          metadata['__dd_allocation_key']
        end
      end
    end
  end
end
