# frozen_string_literal: true

require_relative 'fatal_exceptions'

module Datadog
  module DI
    # Component for dynamic instrumentation.
    #
    # Only one instance of the Component should ever be active;
    # if configuration is changed, the old distance should be shut down
    # prior to the new instance being created.
    #
    # The Component instance stores all state related to DI, for example
    # which probes have been retrieved via remote config,
    # intalled tracepoints and so on. Component will clean up all
    # resources and installed tracepoints upon shutdown.
    class Component
      class << self
        def build(settings, agent_settings, logger, telemetry: nil)
          return unless settings.respond_to?(:dynamic_instrumentation)

          # Explicit DD_DYNAMIC_INSTRUMENTATION_ENABLED=false: do not build the
          # component at all. This is customer intent, not a failure — log at
          # debug and emit no telemetry error. Capabilities#register skips the
          # DI RC block under the same condition, so no enable signal arrives.
          if Remote.explicitly_disabled?(settings)
            logger.debug("di: dynamic instrumentation is explicitly disabled (DD_DYNAMIC_INSTRUMENTATION_ENABLED=false); not building component")
            return
          end

          reason = DI.unsupported_reason(settings)
          if reason
            # Log level mirrors customer intent: if the customer explicitly
            # opted in via DD_DYNAMIC_INSTRUMENTATION_ENABLED, warn. Otherwise
            # debug — with always-build, this path runs on every tracer boot
            # for every customer, including those who never wanted DI. Spamming
            # warnings to silent users (especially on JRuby or Ruby 2.5) would
            # be noise. Customers who later trigger implicit enablement via the
            # Datadog UI get a symmetric warn from Remote.handle_rc_enablement
            # when the RC enable signal finds no component to start.
            level = explicitly_enabled?(settings) ? :warn : :debug
            logger.public_send(level, "di: dynamic instrumentation is disabled: #{reason}")
            return
          end

          new(settings, agent_settings, logger, code_tracker: DI.code_tracker, telemetry: telemetry).tap do |component|
            DI.add_current_component(component)
          end
        end

        # True when the customer explicitly set
        # DD_DYNAMIC_INSTRUMENTATION_ENABLED=true (or its equivalent in code).
        # Symmetric to {Remote.explicitly_disabled?}.
        #
        # Uses {Datadog::Core::Configuration::Options::InstanceMethods#using_default?}
        # rather than `options[:enabled].default_precedence?` because the option
        # hash is populated lazily on first access; reading the underlying option
        # before {Component.build} touches the value would NoMethodError on nil.
        #
        # @param settings [Datadog::Core::Configuration::Settings]
        # @return [Boolean]
        def explicitly_enabled?(settings)
          !settings.dynamic_instrumentation.using_default?(:enabled) &&
            settings.dynamic_instrumentation.enabled
        end
      end

      def initialize(settings, agent_settings, logger, code_tracker: nil, telemetry: nil)
        @settings = settings
        @agent_settings = agent_settings
        logger = DI::Logger.new(settings, logger)
        @logger = logger
        @telemetry = telemetry
        @code_tracker = code_tracker
        @redactor = Redactor.new(settings)
        @serializer = Serializer.new(settings, redactor, telemetry: telemetry)
        @instrumenter = Instrumenter.new(settings, serializer, logger, code_tracker: code_tracker, telemetry: telemetry)
        @probe_repository = ProbeRepository.new
        @probe_notification_builder = ProbeNotificationBuilder.new(settings, serializer, logger, telemetry: telemetry)
        @probe_notifier_worker = ProbeNotifierWorker.new(
          settings, logger,
          agent_settings: agent_settings,
          probe_repository: probe_repository,
          probe_notification_builder: probe_notification_builder,
          telemetry: telemetry,
        )
        @probe_manager = ProbeManager.new(
          settings, instrumenter, probe_notification_builder, probe_notifier_worker, logger, probe_repository,
          telemetry: telemetry,
        )
        # @started transitions are serialized by @lifecycle_mutex so that
        # concurrent RC callbacks (which run on the remote-config thread)
        # cannot race a foreground start! with a background stop!.
        @lifecycle_mutex = Mutex.new
        @started = false
      end

      attr_reader :settings
      attr_reader :agent_settings
      attr_reader :logger
      attr_reader :telemetry
      attr_reader :code_tracker
      attr_reader :instrumenter
      attr_reader :probe_repository
      attr_reader :probe_notifier_worker
      attr_reader :probe_notification_builder
      attr_reader :probe_manager
      attr_reader :redactor
      attr_reader :serializer

      # Starts the DI component: begins accepting probes and
      # processing snapshots.
      #
      # Starts the probe notifier worker thread before enabling the
      # definition trace point, so any future status emission from a
      # trace-point-driven installation has a worker to drain it.
      # Today {ProbeManager#reopen} re-hooks without emitting statuses, so
      # the order is defensive rather than load-bearing. No-op if already
      # started. Serialized by @lifecycle_mutex.
      #
      # @return [void]
      def start!
        @lifecycle_mutex.synchronize do
          return if @started

          probe_notifier_worker.start
          probe_manager.reopen
          @started = true
        end
      end

      # Stops the DI component: removes all probes and stops
      # background threads.
      #
      # The component remains alive and can be restarted with {#start!}.
      # Does not clear out the code tracker.
      # No-op if already stopped. Serialized by @lifecycle_mutex.
      #
      # @return [void]
      def stop!
        @lifecycle_mutex.synchronize do
          return unless @started

          probe_manager.stop
          probe_notifier_worker.stop
          @started = false
        end
      end

      # Whether the component is currently started.
      #
      # Read by remote config dispatch to decide whether to apply probe
      # changes (changes received while stopped are dropped, since the
      # next start! will reconcile from the latest RC state).
      #
      # @return [Boolean] true if start! has been called and stop! has not
      def started?
        @started
      end

      # Shuts down dynamic instrumentation permanently.
      #
      # Removes all code hooks and stops background threads.
      # Called by Components#shutdown! during component destruction.
      # Unlike {#stop!}, this is not reversible.
      #
      # Does not clear out the code tracker, because it's only populated
      # by code when code is compiled and therefore, if the code tracker
      # was replaced by a new instance, the new instance of it wouldn't have
      # any of the already loaded code tracked.
      def shutdown!(replacement = nil)
        DI.remove_current_component(self)

        # Hold the lifecycle mutex so all transitions of @started are
        # serialized — start! / stop! / shutdown! cannot interleave with
        # one another. Without the mutex an in-flight stop! from an RC
        # callback could complete after shutdown!'s probe_manager.close,
        # producing an inconsistent state.
        @lifecycle_mutex.synchronize do
          @started = false
          probe_manager.clear_hooks
          probe_manager.close
          probe_notifier_worker.stop
        end
      end

      def parse_probe_spec_and_notify(probe_spec)
        probe = ProbeBuilder.build_from_remote_config(probe_spec)
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        begin
          probe = Struct.new(:id).new(
            probe_spec['id'],
          )
          payload = probe_notification_builder.build_errored(probe, exc)
          probe_notifier_worker.add_status(payload)
        rescue Exception => nested_exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(nested_exc)
          logger.debug { "di: failed to build error notification: #{nested_exc.class}: #{nested_exc.message}" }
          telemetry&.report(nested_exc, description: 'Error building probe error notification')
          raise
        end

        raise
      else
        payload = probe_notification_builder.build_received(probe)
        probe_notifier_worker.add_status(payload, probe: probe)
        probe
      end
    end
  end
end
