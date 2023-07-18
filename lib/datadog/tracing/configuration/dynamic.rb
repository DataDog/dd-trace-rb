# frozen_string_literal: true

require_relative 'dynamic/option'

module Datadog
  module Tracing
    module Configuration
      module Dynamic
        # Dynamic configuration for `DD_LOGS_INJECTION`.
        class LogInjectionEnabled < SimpleOption
          def initialize
            super('log_injection_enabled', 'DD_LOGS_INJECTION', :log_injection)
          end
        end

        # Dynamic configuration for `DD_TRACE_HEADER_TAGS`.
        class TracingHeaderTags < SimpleOption
          def initialize
            super('tracing_header_tags', 'DD_TRACE_HEADER_TAGS', :header_tags)
          end

          def call(tracing_header_tags)
            # Modify the remote configuration value that it matches the
            # environment variable it configures.
            if tracing_header_tags
              tracing_header_tags.map! do |hash|
                "#{hash['header']}:#{hash['tag_name']}"
              end
            end

            super(tracing_header_tags)
          end
        end

        # Dynamic configuration for `DD_TRACE_SAMPLE_RATE`.
        class TracingSamplingRate < SimpleOption
          def initialize
            super('tracing_sampling_rate', 'DD_TRACE_SAMPLE_RATE', :default_rate)
          end

          # This method ensures that `DD_TRACE_SAMPLE_RATE` will be applied,
          # regardless of competing sampling configuration.
          #
          # Non-competing sampling configurations still apply (e.g. rate limiting).
          def call(tracing_sampling_rate)
            super

            sampler = Tracing::Sampling::PrioritySampler.new(
              base_sampler: Tracing::Sampling::AllSampler.new,
              post_sampler: Tracing::Sampling::RuleSampler.new(
                rate_limit: Datadog.configuration.tracing.sampling.rate_limit,
                default_sample_rate: Datadog.configuration.tracing.sampling.default_rate
              )
            )

            Datadog.send(:components).reconfigure_live_sampler(sampler)
          end

          protected

          def configuration_object
            Datadog.configuration.tracing.sampling
          end
        end

        # List of all tracing dynamic configurations supported.
        OPTIONS = [LogInjectionEnabled, TracingHeaderTags, TracingSamplingRate].map do |option_class|
          option = option_class.new
          [option.name, option.env_var, option]
        end

        # This constant is used a lot in this file, and its path quite long.
        # This shortcut makes it easier to read the rest of this file.
        PRECEDENCE = Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
        private_constant :PRECEDENCE
      end
    end
  end
end
