# frozen_string_literal: true

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

          unless settings.respond_to?(:remote) && settings.remote.enabled
            logger.debug { "di: not building DI component because Remote Configuration Management is not available" }
            return
          end

          return unless environment_supported?(settings, logger)

          new(settings, agent_settings, logger, code_tracker: DI.code_tracker, telemetry: telemetry).tap do |component|
            DI.add_current_component(component)
          end
        end

        # Checks whether the runtime environment is supported by
        # dynamic instrumentation. Currently we only require that, if Rails
        # is used, that Rails environment is not development because
        # DI does not currently support code unloading and reloading.
        def environment_supported?(settings, logger)
          unless settings.dynamic_instrumentation.internal.development
            if Datadog::Core::Environment::Execution.development?
              logger.debug { "di: development environment detected; not building DI component" }
              return false
            end
          end
          if RUBY_ENGINE != 'ruby'
            logger.debug { "di: not building DI component: MRI is required, but running on #{RUBY_ENGINE}" }
            return false
          end
          if RUBY_VERSION < '2.6'
            logger.debug { "di: not building DI component: Ruby 2.6+ is required, but running on #{RUBY_VERSION}" }
            return false
          end
          unless DI.respond_to?(:exception_message)
            logger.debug { "di: not building DI component: C extension is not available" }
            return false
          end
          true
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
        @probe_notification_builder = ProbeNotificationBuilder.new(settings, serializer)
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
      # Starts the probe notifier worker thread and enables the
      # definition trace point for pending method probes.
      # No-op if already started.
      def start!
        return if @started

        probe_notifier_worker.start
        probe_manager.reopen
        @started = true
      end

      # Stops the DI component: removes all probes and stops
      # background threads.
      #
      # The component remains alive and can be restarted with {#start!}.
      # Does not clear out the code tracker.
      # No-op if already stopped.
      def stop!
        return unless @started

        probe_manager.stop
        probe_notifier_worker.stop
        @started = false
      end

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

        @started = false
        probe_manager.clear_hooks
        probe_manager.close
        probe_notifier_worker.stop
      end

      def parse_probe_spec_and_notify(probe_spec)
        probe = ProbeBuilder.build_from_remote_config(probe_spec)
      rescue => exc
        begin
          probe = Struct.new(:id).new(
            probe_spec['id'],
          )
          payload = probe_notification_builder.build_errored(probe, exc)
          probe_notifier_worker.add_status(payload)
        rescue => nested_exc
          logger.debug { "di: failed to build error notification: #{nested_exc.class}: #{nested_exc}" }
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
