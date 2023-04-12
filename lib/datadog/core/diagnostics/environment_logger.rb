require 'date'
require 'json'
require 'rbconfig'

module Datadog
  module Core
    module Diagnostics
      # A holistic collection of the environment in which ddtrace is running.
      # This logger should allow for easy reporting by users to Datadog support.
      #
      module EnvironmentLogger
        class << self
          # Outputs environment information to {Datadog.logger}.
          # Executes only once for the lifetime of the program.
          def log!(transport_responses)
            return if (defined?(@executed) && @executed) || !log?

            @executed = true

            data = EnvironmentCollector.new.collect!(transport_responses)
            data.reject! { |_, v| v.nil? } # Remove empty values from hash output

            log_environment!(data.to_json)
            log_error!('Agent Error'.freeze, data[:agent_error]) if data[:agent_error]
          rescue => e
            Datadog.logger.warn("Failed to collect environment information: #{e} Location: #{Array(e.backtrace).first}")
          end

          private

          def log_environment!(line)
            Datadog.logger.info("DATADOG CONFIGURATION - #{line}")
          end

          def log_error!(type, error)
            Datadog.logger.warn("DATADOG DIAGNOSTIC - #{type}: #{error}")
          end

          # Are we logging the environment data?
          def log?
            startup_logs_enabled = Datadog.configuration.diagnostics.startup_logs.enabled
            if startup_logs_enabled.nil?
              !repl? # Suppress logs if we running in a REPL
            else
              startup_logs_enabled
            end
          end

          REPL_PROGRAM_NAMES = %w[irb pry].freeze

          def repl?
            REPL_PROGRAM_NAMES.include?($PROGRAM_NAME)
          end
        end
      end

      # Collects environment information for diagnostic logging
      class EnvironmentCollector
        # @return [String] current time in ISO8601 format
        def date
          DateTime.now.iso8601
        end

        # Best portable guess of OS information.
        # @return [String] platform string
        def os_name
          RbConfig::CONFIG['host'.freeze]
        end

        # @return [String] ddtrace version
        def version
          DDTrace::VERSION::STRING
        end

        # @return [String] "ruby"
        def lang
          Core::Environment::Ext::LANG
        end

        # Supported Ruby language version.
        # Will be distinct from VM version for non-MRI environments.
        # @return [String]
        def lang_version
          Core::Environment::Ext::LANG_VERSION
        end

        # @return [String] configured application environment
        def env
          Datadog.configuration.env
        end

        # @return [Boolean, nil]
        def enabled
          Datadog.configuration.tracing.enabled
        end

        # @return [String] configured application service name
        def service
          Datadog.configuration.service
        end

        # @return [String] configured application version
        def dd_version
          Datadog.configuration.version
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
        def agent_error(transport_responses)
          error_responses = transport_responses.reject(&:ok?)

          return nil if error_responses.empty?

          error_responses.map(&:inspect).join(','.freeze)
        end

        # @return [Boolean, nil] debug mode enabled in configuration
        def debug
          !!Datadog.configuration.diagnostics.debug
        end

        # @return [Boolean, nil] analytics enabled in configuration
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

        # @return [Hash, nil] concatenated list of global tracer tags configured
        def tags
          tags = Datadog.configuration.tags
          return nil if tags.empty?

          hash_serializer(tags)
        end

        # @return [Boolean, nil] runtime metrics enabled in configuration
        def runtime_metrics_enabled
          Datadog.configuration.runtime_metrics.enabled
        end

        # Concatenated list of integrations activated, with their gem version.
        # Example: "rails@6.0.3,rack@2.2.3"
        #
        # @return [String, nil]
        def integrations_loaded
          integrations = instrumented_integrations
          return if integrations.empty?

          integrations.map { |name, integration| "#{name}@#{integration.class.version}" }.join(','.freeze)
        end

        # Ruby VM name and version.
        # Examples: "ruby-2.7.1", "jruby-9.2.11.1", "truffleruby-20.1.0"
        # @return [String, nil]
        def vm
          # RUBY_ENGINE_VERSION returns the VM version, which
          # will differ from RUBY_VERSION for non-mri VMs.
          if defined?(RUBY_ENGINE_VERSION)
            "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
          else
            # Ruby < 2.3 doesn't support RUBY_ENGINE_VERSION
            "#{RUBY_ENGINE}-#{RUBY_VERSION}"
          end
        end

        # @return [Boolean, nil] partial flushing enabled in configuration
        def partial_flushing_enabled
          !!Datadog.configuration.tracing.partial_flush.enabled
        end

        # @return [Boolean, nil] priority sampling enabled in configuration
        def priority_sampling_enabled
          !!Datadog.configuration.tracing.priority_sampling
        end

        # @return [Boolean, nil] health metrics enabled in configuration
        def health_metrics_enabled
          !!Datadog.configuration.diagnostics.health_metrics.enabled
        end

        def profiling_enabled
          !!Datadog.configuration.profiling.enabled
        end

        # TODO: Populate when automatic log correlation is implemented
        # def logs_correlation_enabled
        # end

        # @return [Hash] environment information available at call time
        def collect!(transport_responses)
          {
            date: date,
            os_name: os_name,
            version: version,
            lang: lang,
            lang_version: lang_version,
            env: env,
            enabled: enabled,
            service: service,
            dd_version: dd_version,
            agent_url: agent_url,
            agent_error: agent_error(transport_responses),
            debug: debug,
            analytics_enabled: analytics_enabled,
            sample_rate: sample_rate,
            sampling_rules: sampling_rules,
            tags: tags,
            runtime_metrics_enabled: runtime_metrics_enabled,
            integrations_loaded: integrations_loaded,
            vm: vm,
            partial_flushing_enabled: partial_flushing_enabled,
            priority_sampling_enabled: priority_sampling_enabled,
            health_metrics_enabled: health_metrics_enabled,
            profiling_enabled: profiling_enabled,
            **instrumented_integrations_settings
          }
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

        # Outputs "k1:v1,k2:v2,..."
        def hash_serializer(h)
          h.map { |k, v| "#{k}:#{v}" }.join(','.freeze)
        end
      end
    end
  end
end
