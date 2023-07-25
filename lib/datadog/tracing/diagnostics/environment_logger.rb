require 'date'
require 'json'
require 'rbconfig'
require_relative '../../core/diagnostics/environment_logger'

module Datadog
  module Tracing
    module Diagnostics
      # Collects tracing environment information for diagnostic logging
      module TracingEnvironmentCollector
        # @return [Boolean, nil]
        def enabled
          Datadog.configuration.tracing.enabled
        end

        # @return [String, nil] target agent URL for trace flushing
        def agent_url
          # Retrieve the effect agent URL, regardless of how it was configured
          transport = Tracing.send(:tracer).writer.transport

          # return `nil` with IO transport
          return unless transport.respond_to?(:client)

          adapter = transport.client.api.adapter
          adapter.url
        end

        # Error returned by Datadog agent during a tracer flush attempt
        # @return [String] concatenated list of transport errors
        def agent_error(tracing_responses)
          return nil if tracing_responses.nil?
          
          error_responses = tracing_responses.reject(&:ok?)

          return nil if error_responses.empty?

          error_responses.map(&:inspect).join(','.freeze)
        end

        def analytics_enabled
          !!Datadog.configuration.tracing.analytics.enabled
        end

        # @return [Numeric, nil] tracer sample rate configured
        def sample_rate
          sampler = Datadog.configuration.tracing.sampler
          return nil unless sampler

          sampler.sample_rate(nil) rescue nil
        end

        # DEV: We currently only support SimpleRule instances.
        # DEV: These are the most commonly used rules.
        # DEV: We should expand support for other rules in the future,
        # DEV: although it is tricky to serialize arbitrary rules.
        #
        # @return [Hash, nil] sample rules configured
        def sampling_rules
          sampler = Datadog.configuration.tracing.sampler
          return nil unless sampler.is_a?(Tracing::Sampling::PrioritySampler) &&
            sampler.priority_sampler.is_a?(Tracing::Sampling::RuleSampler)

          sampler.priority_sampler.rules.map do |rule|
            next unless rule.is_a?(Tracing::Sampling::SimpleRule)

            {
              name: rule.matcher.name,
              service: rule.matcher.service,
              sample_rate: rule.sampler.sample_rate(nil)
            }
          end.compact
        end

        def partial_flushing_enabled
          !!Datadog.configuration.tracing.partial_flush.enabled
        end

        # @return [Boolean, nil] priority sampling enabled in configuration
        def priority_sampling_enabled
          !!Datadog.configuration.tracing.priority_sampling
        end

        def collect!(**data)
          super.merge(
            enabled: enabled,
            agent_url: agent_url,
            analytics_enabled: analytics_enabled,
            sample_rate: sample_rate,
            sampling_rules: sampling_rules,
            partial_flushing_enabled: partial_flushing_enabled,
            priority_sampling_enabled: priority_sampling_enabled,
            **instrumented_integrations_settings
          )
        end

        def collect_errors!(**data)
          super << ['Agent Error', agent_error(data[:tracing_responses])]
        end

        private

        def instrumented_integrations
          Datadog.configuration.tracing.instrumented_integrations
        end

        # Capture all active integration settings into "integrationName_settingName: value" entries.
        def instrumented_integrations_settings
          instrumented_integrations.flat_map do |name, integration|
            integration.configuration.to_h.flat_map do |setting, value|
              next [] if setting == :tracer # Skip internal Ruby objects

              # Convert value to a string to avoid custom #to_json
              # handlers possibly causing errors.
              [[:"integration_#{name}_#{setting}", value.to_s]]
            end
          end.to_h
        end
      end

      Core::Diagnostics::EnvironmentCollector.prepend(TracingEnvironmentCollector)
    end
  end
end
