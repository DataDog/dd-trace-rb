require_relative 'agent_settings_resolver'
require_relative '../diagnostics/environment_logger'
require_relative '../diagnostics/health'
require_relative '../logger'
require_relative '../runtime/metrics'
require_relative '../telemetry/client'
require_relative '../workers/runtime_metrics'

require_relative '../../tracing/component'
require_relative '../../profiling/component'
require_relative '../../appsec/component'

module Datadog
  module Core
    module Configuration
      # Global components for the trace library.
      class Components
        class << self
          include Datadog::Tracing::Component
          include Datadog::Profiling::Component

          def build_health_metrics(settings)
            settings = settings.diagnostics.health_metrics
            options = { enabled: settings.enabled }
            options[:statsd] = settings.statsd unless settings.statsd.nil?

            Core::Diagnostics::Health::Metrics.new(**options)
          end

          def build_logger(settings)
            logger = settings.logger.instance || Core::Logger.new($stdout)
            logger.level = settings.diagnostics.debug ? ::Logger::DEBUG : settings.logger.level

            logger
          end

          def build_runtime_metrics(settings)
            options = { enabled: settings.runtime_metrics.enabled }
            options[:statsd] = settings.runtime_metrics.statsd unless settings.runtime_metrics.statsd.nil?
            options[:services] = [settings.service] unless settings.service.nil?

            Core::Runtime::Metrics.new(**options)
          end

          def build_runtime_metrics_worker(settings)
            # NOTE: Should we just ignore building the worker if its not enabled?
            options = settings.runtime_metrics.opts.merge(
              enabled: settings.runtime_metrics.enabled,
              metrics: build_runtime_metrics(settings)
            )

            Core::Workers::RuntimeMetrics.new(options)
          end

          def build_telemetry(settings)
            Telemetry::Client.new(enabled: settings.telemetry.enabled)
          end
        end

        attr_reader \
          :health_metrics,
          :logger,
          :profiler,
          :runtime_metrics,
          :telemetry,
          :tracer,
          :appsec

        def initialize(settings)
          # Logger
          @logger = self.class.build_logger(settings)

          agent_settings = AgentSettingsResolver.call(settings, logger: @logger)

          # Tracer
          @tracer = self.class.build_tracer(settings, agent_settings)

          # Profiler
          @profiler = self.class.build_profiler(settings, agent_settings, @tracer)

          # Runtime metrics
          @runtime_metrics = self.class.build_runtime_metrics_worker(settings)

          # Health metrics
          @health_metrics = self.class.build_health_metrics(settings)

          # Telemetry
          @telemetry = self.class.build_telemetry(settings)

          # AppSec
          @appsec = Datadog::AppSec::Component.build_appsec_component(settings.appsec)
        end

        # Starts up components
        def startup!(settings)
          if settings.profiling.enabled
            if profiler
              @logger.debug('Profiling started')
              profiler.start
            else
              # Display a warning for users who expected profiling to be enabled
              unsupported_reason = Profiling.unsupported_reason
              logger.warn("Profiling was requested but is not supported, profiling disabled: #{unsupported_reason}")
            end
          else
            @logger.debug('Profiling is disabled')
          end
        end

        # Shuts down all the components in use.
        # If it has another instance to compare to, it will compare
        # and avoid tearing down parts still in use.
        def shutdown!(replacement = nil)
          # Decommission AppSec
          appsec.shutdown! if appsec

          # Shutdown the old tracer, unless it's still being used.
          # (e.g. a custom tracer instance passed in.)
          tracer.shutdown! unless replacement && tracer == replacement.tracer

          # Shutdown old profiler
          profiler.shutdown! unless profiler.nil?

          # Shutdown workers
          runtime_metrics.stop(true, close_metrics: false)

          # Shutdown the old metrics, unless they are still being used.
          # (e.g. custom Statsd instances.)
          #
          # TODO: This violates the encapsulation created by Runtime::Metrics and
          # Health::Metrics, by directly manipulating `statsd` and changing
          # it's lifecycle management.
          # If we need to directly have ownership of `statsd` lifecycle, we should
          # have direct ownership of it.
          old_statsd = [
            runtime_metrics.metrics.statsd,
            health_metrics.statsd
          ].compact.uniq

          new_statsd =  if replacement
                          [
                            replacement.runtime_metrics.metrics.statsd,
                            replacement.health_metrics.statsd
                          ].compact.uniq
                        else
                          []
                        end

          unused_statsd = (old_statsd - (old_statsd & new_statsd))
          unused_statsd.each(&:close)

          telemetry.stop!
          telemetry.emit_closing! unless replacement
        end
      end
    end
  end
end
