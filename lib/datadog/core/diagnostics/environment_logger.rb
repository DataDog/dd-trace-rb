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
          def log!(**data)
            return if (defined?(@executed) && @executed) || !log?

            @executed = true

            collector = EnvironmentCollector.new

            collected_data = collector.collect!(**data)
            collected_data.reject! { |_, v| v.nil? } # Remove empty values from hash
            log_environment!(collected_data.to_json)

            errors = collector.collect_errors!(**data)
            errors.reject! { |_, message| message.nil? } # Remove empty values from list
            errors.each do |type, message|
              log_error!(type, message)
            end
          rescue => e
            Datadog.logger.warn("Failed to collect environment information: #{e} Location: #{Array(e.backtrace).first}")
          end

          private

          def log_environment!(line)
            Datadog.logger.info("DATADOG CONFIGURATION - #{line}")
          end

          def log_error!(type, message)
            Datadog.logger.warn("DATADOG DIAGNOSTIC - #{type}: #{message}")
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

        # @return [String] configured application service name
        def service
          Datadog.configuration.service
        end

        # @return [String] configured application version
        def dd_version
          Datadog.configuration.version
        end

        # @return [Boolean, nil] debug mode enabled in configuration
        def debug
          !!Datadog.configuration.diagnostics.debug
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

        # @return [Boolean, nil] health metrics enabled in configuration
        def health_metrics_enabled
          !!Datadog.configuration.diagnostics.health_metrics.enabled
        end

        # TODO: Populate when automatic log correlation is implemented
        # def logs_correlation_enabled
        # end

        # @return [Hash] environment information available at call time
        def collect!(**data)
          {
            date: date,
            os_name: os_name,
            version: version,
            lang: lang,
            lang_version: lang_version,
            env: env,
            service: service,
            dd_version: dd_version,
            debug: debug,
            tags: tags,
            runtime_metrics_enabled: runtime_metrics_enabled,
            integrations_loaded: integrations_loaded,
            vm: vm,
            health_metrics_enabled: health_metrics_enabled,
          }
        end

        def collect_errors!(**data)
          [
            # List of [error type, error message]
          ]
        end

        private

        # Outputs "k1:v1,k2:v2,..."
        def hash_serializer(h)
          h.map { |k, v| "#{k}:#{v}" }.join(','.freeze)
        end
      end
    end
  end
end




# have base environment logger
#   exposes log that takes arbitrary data