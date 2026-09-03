# frozen_string_literal: true

require "json"
require "rbconfig"
require "time"

module Datadog
  module Core
    module Diagnostics
      # Base class for EnvironmentLoggers - should allow for easy reporting by users to Datadog support.
      #
      # The EnvironmentLogger should not pollute the logs in a development environment.
      module EnvironmentLogging
        def log_configuration!(prefix, data)
          logger.info("DATADOG CONFIGURATION - #{prefix} - #{data}")
        end

        def log_debug!(prefix, data)
          logger.debug("DATADOG CONFIGURATION - #{prefix} - #{data}")
        end

        def log_error!(prefix, type, error)
          logger.warn("DATADOG ERROR - #{prefix} - #{type}: #{error}")
        end

        protected

        def logger
          Datadog.logger
        end

        def log?
          startup_logs_enabled = Datadog.configuration.diagnostics.startup_logs.enabled
          if startup_logs_enabled.nil?
            # Do not pollute the logs in a development environment.
            !Datadog::Core::Environment::Execution.development?
          else
            startup_logs_enabled
          end
        end
      end

      module EnvironmentLogger
        extend EnvironmentLogging

        def self.collect_and_log!(extra_fields = nil)
          if log?
            data = EnvironmentCollector.collect_config!
            data = data.merge(extra_fields) if extra_fields
            log_configuration!("CORE", data.to_json)
          end
        rescue => e
          logger.warn(
            "Failed to collect core environment information: #{e.class}: #{e.message} Location: #{Array(e.backtrace).first}"
          )
        end
      end

      module EnvironmentCollector
        class << self
          def collect_config!
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
              vm: vm,
              health_metrics_enabled: health_metrics_enabled,
              otlp_traces_export_enabled: otlp_traces_export_enabled,
              otlp_metrics_export_enabled: otlp_metrics_export_enabled,
              otlp_logs_export_enabled: otlp_logs_export_enabled,
            }
          end

          def date
            Core::Utils::Time.now.utc.iso8601
          end

          # Best portable guess of OS information.
          def os_name
            RbConfig::CONFIG["host"]
          end

          def version
            Datadog::VERSION::STRING
          end

          def lang
            Core::Environment::Ext::LANG
          end

          # Supported Ruby language version.
          # Will be distinct from VM version for non-MRI environments.
          def lang_version
            Core::Environment::Ext::LANG_VERSION
          end

          def env
            Datadog.configuration.env
          end

          def service
            Datadog.configuration.service
          end

          def dd_version
            Datadog.configuration.version
          end

          def debug
            !!Datadog.configuration.diagnostics.debug
          end

          def tags
            tags = Datadog.configuration.tags
            return nil if tags.empty?

            hash_serializer(tags)
          end

          def runtime_metrics_enabled
            Datadog.configuration.runtime_metrics.enabled
          end

          # Ruby VM name and version.
          # Examples: "ruby-2.7.1", "jruby-9.2.11.1", "truffleruby-20.1.0"
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

          def health_metrics_enabled
            !!Datadog.configuration.health_metrics.enabled
          end

          # @return [Boolean] whether the tracer exports traces over OTLP.
          #   Always false: Ruby exports spans in Datadog's native format and has no OTLP trace exporter.
          def otlp_traces_export_enabled
            false
          end

          def otlp_metrics_export_enabled
            metrics = opentelemetry_settings&.metrics
            # A "none" exporter skips the OTLP metric reader even when metrics are enabled
            # (mirrors Datadog::OpenTelemetry::Ext::EXPORTER_NONE).
            !!(metrics&.enabled && metrics.exporter != "none")
          end

          def otlp_logs_export_enabled
            logs = opentelemetry_settings&.logs
            # A "none" exporter skips the OTLP log record processor even when logs are enabled
            # (mirrors Datadog::OpenTelemetry::Ext::EXPORTER_NONE).
            !!(logs&.enabled && logs.exporter != "none")
          end

          private

          # The `opentelemetry` settings namespace is registered by core configuration, but access it
          # defensively so a missing/unregistered namespace defaults to `false` rather than raising.
          def opentelemetry_settings
            return unless Datadog.configuration.respond_to?(:opentelemetry)

            Datadog.configuration.opentelemetry
          rescue
            nil
          end

          # Outputs "k1:v1,k2:v2,..."
          def hash_serializer(h)
            h.map { |k, v| "#{k}:#{v}" }.join(",")
          end
        end
      end
    end
  end
end
