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
        class TracingSamplingRate < Option
          def initialize
            super('tracing_sampling_rate', 'DD_TRACE_SAMPLE_RATE')
          end

          # `DD_TRACE_SAMPLE_RATE` can be overridden by many options.
          # This method ensures that all related options are cleared when setting `DD_TRACE_SAMPLE_RATE`.
          def call(tracing_sampling_rate)
            configuration = Datadog.configuration
            tracing = configuration.tracing

            if tracing_sampling_rate.nil?
              tracing.sampling.unset_option(:default_rate, precedence: PRECEDENCE)

              tracing.test_mode.unset_option(:enabled, precedence: PRECEDENCE)
              tracing.sampling.unset_option(:rules, precedence: PRECEDENCE)
              tracing.unset_option(:sampler, precedence: PRECEDENCE)
              tracing.unset_option(:priority_sampling, precedence: PRECEDENCE)
            else
              tracing.sampling.set_option(:default_rate, tracing_sampling_rate, precedence: PRECEDENCE)

              # These options affect how the sampler is constructed.
              # We change them to guarantee that the tracer will respect the configured `default_rate`.
              tracing.test_mode.set_option(:enabled, false, precedence: PRECEDENCE)
              tracing.sampling.set_option(:rules, nil, precedence: PRECEDENCE)
              tracing.set_option(:sampler, nil, precedence: PRECEDENCE)
              tracing.set_option(:priority_sampling, nil, precedence: PRECEDENCE)
            end

            # Ensures there is not concurrent configuration or reconfiguration during
            # the sampling swap.
            Datadog.send(:safely_synchronize) do
              Datadog.send(:components).reconfigure_sampler(configuration)
            end
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
