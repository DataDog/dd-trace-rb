# frozen_string_literal: true

require_relative '../ext'

module Datadog
  module OpenFeature
    module Hooks
      # EVP flagevaluation hook — structural copy of FlagEvalMetricsHook for the new EVP path.
      #
      # This hook does ONLY cheap capture + non-blocking enqueue on the caller's eval thread.
      # All aggregation (canonical key, tier routing, cap enforcement) is performed
      # in the background by the FlagEvaluation::Writer.
      #
      # OTel non-regression: hooks/flag_eval_metrics_hook.rb and metrics/flag_eval_metrics.rb
      # stay on the OTel path. This hook is registered as a provider hook so it receives
      # the SDK-final EvaluationDetails after hook failures and type validation.
      class FlagEvalEVPHook
        TYPE_MISMATCH_ERROR_CODE = 'TYPE_MISMATCH'

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
            variant: evaluation_details.variant,
            allocation_key: extract_allocation_key(evaluation_details),
            error_message: extract_error_message(evaluation_details),
            runtime_default: runtime_default?(evaluation_details),
            targeting_key: extract_targeting_key(hook_context.evaluation_context),
            eval_time_ms: eval_time_ms,
            attrs: extract_attributes(hook_context.evaluation_context),
          )
        end

        private

        def extract_targeting_key(evaluation_context)
          return unless evaluation_context&.respond_to?(:targeting_key)

          evaluation_context.targeting_key
        end

        def extract_attributes(evaluation_context)
          return {} unless evaluation_context

          if evaluation_context.respond_to?(:attributes)
            return evaluation_context.attributes || {}
          end

          return {} unless evaluation_context.respond_to?(:fields)

          fields = evaluation_context.fields
          return {} unless fields.is_a?(Hash)

          fields.reject { |k, _| k.to_s == ::OpenFeature::SDK::EvaluationContext::TARGETING_KEY }
        end

        def extract_allocation_key(evaluation_details)
          metadata = evaluation_details.flag_metadata
          return unless metadata.is_a?(Hash)

          metadata[Ext::METADATA_ALLOCATION_KEY]
        end

        def extract_error_message(evaluation_details)
          return unless evaluation_details.respond_to?(:error_message)

          evaluation_details.error_message
        end

        def runtime_default?(evaluation_details)
          return true if evaluation_details.variant.nil?
          return false unless evaluation_details.respond_to?(:error_code)

          evaluation_details.error_code.to_s == TYPE_MISMATCH_ERROR_CODE
        end
      end
    end
  end
end
