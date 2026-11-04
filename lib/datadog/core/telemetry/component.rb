# frozen_string_literal: true

require_relative "event"
require_relative "logging"
require_relative "native_backend"
require_relative "ruby_backend"

require_relative "../configuration/ext"
require_relative "../utils/forking"

module Datadog
  module Core
    module Telemetry
      # Telemetry entry point, coordinates sending telemetry events at
      # various points in application lifecycle.
      #
      # @api private
      class Component
        ENDPOINT_COLLECTION_MESSAGE_LIMIT = 300

        attr_reader :enabled
        attr_reader :logger
        attr_reader :settings
        attr_reader :agent_settings
        attr_reader :backend

        # Alias for consistency with other components.
        # TODO Remove +enabled+ method
        alias_method :enabled?, :enabled

        include Core::Utils::Forking
        include Telemetry::Logging

        def self.build(settings, agent_settings, logger)
          enabled = settings.telemetry.enabled
          agentless_enabled = settings.telemetry.agentless_enabled

          if agentless_enabled && settings.api_key.nil?
            enabled = false
            logger.debug { "Telemetry disabled. Agentless telemetry requires a DD_API_KEY variable to be set." }
          end

          Telemetry::Component.new(
            settings: settings,
            agent_settings: agent_settings,
            enabled: enabled,
            logger: logger,
          )
        end

        def transport
          backend.transport
        end

        def worker
          backend.worker
        end

        def metrics_manager
          backend.metrics_manager
        end

        # @param enabled [Boolean] Determines whether telemetry events will be sent to the API
        def initialize(
          settings:,
          agent_settings:,
          logger:,
          enabled:
        )
          @enabled = enabled
          @log_collection_enabled = settings.telemetry.log_collection_enabled
          @logger = logger
          @settings = settings
          @agent_settings = agent_settings

          @backend = if settings.telemetry.native_worker && NativeBackend.unsupported_reason.nil?
            NativeBackend.new(
              settings: settings,
              agent_settings: agent_settings,
              logger: logger,
              enabled: enabled,
            )
          else
            RubyBackend.new(
              settings: settings,
              agent_settings: agent_settings,
              logger: logger,
              enabled: enabled,
            )
          end
        end

        def disable!
          @enabled = false
          @backend.disable!
        end

        def start(initial_event_is_change = false, components:)
          return unless enabled?

          initial_event = if initial_event_is_change
            Event::SynthAppClientConfigurationChange.new(
              components: components,
            )
          else
            Event::AppStarted.new(
              components: components,
            )
          end

          @backend.start(initial_event)
        end

        def shutdown!
          @backend.shutdown!
        end

        def emit_closing!
          return unless enabled?

          @backend.enqueue(Event::AppClosing.new)
        end

        def integrations_change!
          return unless enabled?

          @backend.enqueue(Event::AppIntegrationsChange.new)
        end

        def log!(event)
          return unless enabled? && @log_collection_enabled

          @backend.add_log(event)
        end

        # Wait for the worker to send out all events that have already
        # been queued, up to 15 seconds. Returns whether all events have
        # been flushed, or nil if telemetry is disabled.
        #
        # @api private
        def flush(timeout: nil)
          return unless enabled?

          @backend.flush(timeout: timeout)
        end

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return unless enabled?

          @backend.enqueue(Event::AppClientConfigurationChange.new(changes, "remote_config"))
        end

        # Report application endpoints
        def app_endpoints_loaded(endpoints, page_size: ENDPOINT_COLLECTION_MESSAGE_LIMIT)
          return unless enabled?

          endpoints.each_slice(page_size).with_index do |endpoints_slice, i|
            @backend.enqueue(Event::AppEndpointsLoaded.new(endpoints_slice, is_first: i.zero?))
          end
        end

        # Increments a count metric.
        def inc(namespace, metric_name, value, tags: {}, common: true)
          @backend.inc(namespace, metric_name, value, tags: tags, common: common)
        end

        # Decremenets a count metric.
        def dec(namespace, metric_name, value, tags: {}, common: true)
          @backend.dec(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks gauge metric.
        def gauge(namespace, metric_name, value, tags: {}, common: true)
          @backend.gauge(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks rate metric.
        def rate(namespace, metric_name, value, tags: {}, common: true)
          @backend.rate(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks distribution metric.
        def distribution(namespace, metric_name, value, tags: {}, common: true)
          @backend.distribution(namespace, metric_name, value, tags: tags, common: common)
        end

        def after_fork
          @backend.after_fork
        end
      end
    end
  end
end
