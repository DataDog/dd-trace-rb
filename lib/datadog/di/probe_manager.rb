# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

require 'monitor'

module Datadog
  module DI
    # Stores probes received from remote config (that we can parse, in other
    # words, whose type/attributes we support), requests needed instrumentation
    # for the probes via Instrumenter, and stores pending probes (those which
    # haven't yet been instrumented successfully due to their targets not
    # existing) and failed probes (where we are certain the target will not
    # ever be loaded, or otherwise become valid).
    #
    # @api private
    class ProbeManager
      def initialize(settings, instrumenter, probe_notification_builder,
        probe_notifier_worker, logger, telemetry: nil)
        @settings = settings
        @instrumenter = instrumenter
        @probe_notification_builder = probe_notification_builder
        @probe_notifier_worker = probe_notifier_worker
        @logger = logger
        @telemetry = telemetry
        @installed_probes = {}
        @pending_probes = {}
        @failed_probes = {}
        @lock = Monitor.new

        @definition_trace_point = TracePoint.trace(:end) do |tp|
          install_pending_method_probes(tp.self)
        rescue => exc
          raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
          logger.debug { "di: unhandled exception in definition trace point: #{exc.class}: #{exc}" }
          telemetry&.report(exc, description: "Unhandled exception in definition trace point")
          # TODO test this path
        end
      end

      attr_reader :logger
      attr_reader :telemetry

      # TODO test that close is called during component teardown and
      # the trace point is cleared
      def close
        definition_trace_point.disable
        clear_hooks
      end

      def clear_hooks
        @lock.synchronize do
          @pending_probes.clear
          @installed_probes.each do |probe_id, probe|
            instrumenter.unhook(probe)
          end
          @installed_probes.clear
        end
      end

      attr_reader :settings
      attr_reader :instrumenter
      attr_reader :probe_notification_builder
      attr_reader :probe_notifier_worker

      def installed_probes
        @lock.synchronize do
          @installed_probes
        end
      end

      def pending_probes
        @lock.synchronize do
          @pending_probes
        end
      end

      # Probes that failed to instrument for reasons other than the target is
      # not yet loaded are added to this collection, so that we do not try
      # to instrument them every time remote configuration is processed.
      def failed_probes
        @lock.synchronize do
          @failed_probes
        end
      end

      # Requests to install the specified probe.
      #
      # If the target of the probe does not exist, assume the relevant
      # code is not loaded yet (rather than that it will never be loaded),
      # and store the probe in a pending probe list. When classes are
      # defined, or files loaded, the probe will be checked against the
      # newly defined classes/loaded files, and will be installed if it
      # matches.
      def add_probe(probe)
        @lock.synchronize do
          if @installed_probes[probe.id]
            # Either this probe was already installed, or another probe was
            # installed with the same id (previous version perhaps?).
            # Since our state tracking is keyed by probe id, we cannot
            # install this probe since we won't have a way of removing the
            # instrumentation for the probe with the same id which is already
            # installed.
            #
            # The exception raised here will be caught below and logged and
            # reported to telemetry.
            raise Error::AlreadyInstrumented, "Probe with id #{probe.id} is already in installed probes"
          end

          # Probe failed to install previously, do not try to install it again.
          if msg = @failed_probes[probe.id]
            # TODO test this path
            raise Error::ProbePreviouslyFailed, msg
          end

          begin
            instrumenter.hook(probe, self)

            @installed_probes[probe.id] = probe
            payload = probe_notification_builder.build_installed(probe)
            probe_notifier_worker.add_status(payload, probe: probe)
            # The probe would only be in the pending probes list if it was
            # previously attempted to be installed and the target was not loaded.
            # Always remove from pending list here because it makes the
            # API smaller and shouldn't cause any actual problems.
            @pending_probes.delete(probe.id)
            logger.trace { "di: installed #{probe.type} probe at #{probe.location} (#{probe.id})" }
            true
          rescue Error::DITargetNotDefined
            @pending_probes[probe.id] = probe
            logger.trace { "di: could not install #{probe.type} probe at #{probe.location} (#{probe.id}) because its target is not defined, adding it to pending list" }
            false
          end
        rescue => exc
          # In "propagate all exceptions" mode we will try to instrument again.
          raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

          logger.debug { "di: error processing probe configuration: #{exc.class}: #{exc}" }
          telemetry&.report(exc, description: "Error processing probe configuration")
          # TODO report probe as failed to agent since we won't attempt to
          # install it again.

          # TODO add top stack frame to message
          @failed_probes[probe.id] = "#{exc.class}: #{exc}"

          raise
        end
      end

      # Removes probe with specified id. The probe could be pending or
      # installed. Does nothing if there is no probe with the specified id.
      def remove_probe(probe_id)
        @lock.synchronize do
          @pending_probes.delete(probe_id)
        end

        # Do not delete the probe from the registry here in case
        # deinstrumentation fails - though I don't know why deinstrumentation
        # would fail and how we could recover if it does.
        # I plan on tracking the number of outstanding (instrumented) probes
        # in the future, and if deinstrumentation fails I would want to
        # keep that probe as "installed" for the count, so that we can
        # investigate the situation.
        if probe = @installed_probes[probe_id]
          begin
            instrumenter.unhook(probe)
            @installed_probes.delete(probe_id)
          rescue => exc
            raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
            # Silence all exceptions?
            # TODO should we propagate here and rescue upstream?
            logger.debug { "di: error removing #{probe.type} probe at #{probe.location} (#{probe.id}): #{exc.class}: #{exc}" }
            telemetry&.report(exc, description: "Error removing probe")
          end
        end
      end

      # Installs pending method probes, if any, for the specified class.
      #
      # This method is meant to be called from the "end" trace point,
      # which is invoked for each class definition.
      private def install_pending_method_probes(cls)
        @lock.synchronize do
          # TODO search more efficiently than linearly
          @pending_probes.each do |probe_id, probe|
            if probe.method?
              # TODO move this stringification elsewhere
              if probe.type_name == cls.name
                begin
                  # TODO is it OK to hook from trace point handler?
                  # TODO the class is now defined, but can hooking still fail?
                  instrumenter.hook(probe, self)
                  @installed_probes[probe.id] = probe
                  @pending_probes.delete(probe.id)
                  break
                rescue Error::DITargetNotDefined
                  # This should not happen... try installing again later?
                rescue => exc
                  raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                  logger.debug { "di: error installing #{probe.type} probe at #{probe.location} (#{probe.id}) after class is defined: #{exc.class}: #{exc}" }
                  telemetry&.report(exc, description: "Error installing probe after class is defined")
                end
              end
            end
          end
        end
      end

      # Installs pending line probes, if any, for the file of the specified
      # absolute path.
      #
      # This method is meant to be called from the script_compiled trace
      # point, which is invoked for each required or loaded file
      # (and also for eval'd code, but those invocations are filtered out).
      def install_pending_line_probes(path)
        if path.nil?
          raise ArgumentError, "path must not be nil"
        end
        @lock.synchronize do
          @pending_probes.values.each do |probe|
            if probe.line?
              if probe.file_matches?(path)
                add_probe(probe)
              end
            end
          end
        end
      end

      # Entry point invoked from the instrumentation when the specfied probe
      # is invoked (that is, either its target method is invoked, or
      # execution reached its target file/line).
      #
      # This method is responsible for queueing probe status to be sent to the
      # backend (once per the probe's lifetime) and a snapshot corresponding
      # to the current invocation.
      def probe_executed_callback(context)
        probe = context.probe
        logger.trace { "di: executed #{probe.type} probe at #{probe.location} (#{probe.id})" }
        unless probe.emitting_notified?
          payload = probe_notification_builder.build_emitting(probe)
          probe_notifier_worker.add_status(payload, probe: probe)
          probe.emitting_notified = true
        end

        payload = probe_notification_builder.build_executed(context)
        probe_notifier_worker.add_snapshot(payload)
      end

      def probe_condition_evaluation_failed_callback(context, expr, exc)
        probe = context.probe
        if probe.condition_evaluation_failed_rate_limiter&.allow?
          payload = probe_notification_builder.build_condition_evaluation_failed(context, expr, exc)
          probe_notifier_worker.add_snapshot(payload)
        end
      end

      def probe_disabled_callback(probe, duration)
        payload = probe_notification_builder.build_disabled(probe, duration)
        probe_notifier_worker.add_status(payload, probe: probe)
      end

      # Class/module definition trace point (:end type).
      # Used to install hooks when the target classes/modules aren't yet
      # defined when the hook request is received.
      attr_reader :definition_trace_point
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
