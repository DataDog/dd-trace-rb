# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

module Datadog
  module DI
    # Orchestrates probe lifecycle: installation, removal, and execution callbacks.
    # Delegates probe storage to ProbeRepository.
    #
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
        probe_notifier_worker, logger, probe_repository, telemetry: nil)
        @settings = settings
        @instrumenter = instrumenter
        @probe_notification_builder = probe_notification_builder
        @probe_notifier_worker = probe_notifier_worker
        @logger = logger
        @telemetry = telemetry
        @probe_repository = probe_repository

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
      attr_reader :probe_repository

      # TODO test that close is called during component teardown and
      # the trace point is cleared
      def close
        definition_trace_point.disable
        clear_hooks
      end

      def clear_hooks
        probe_repository.clear_all do |probe|
          instrumenter.unhook(probe)
        end
      end

      attr_reader :settings
      attr_reader :instrumenter
      attr_reader :probe_notification_builder
      attr_reader :probe_notifier_worker

      # Requests to install the specified probe.
      #
      # If the target of the probe does not exist, assume the relevant
      # code is not loaded yet (rather than that it will never be loaded),
      # and store the probe in a pending probe list. When classes are
      # defined, or files loaded, the probe will be checked against the
      # newly defined classes/loaded files, and will be installed if it
      # matches.
      #
      # On successful installation, sends INSTALLED status to the backend.
      # On failure, sends ERROR status to the backend before re-raising.
      def add_probe(probe)
        if probe_repository.find_installed(probe.id)
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
        if msg = probe_repository.find_failed(probe.id)
          # TODO test this path
          raise Error::ProbePreviouslyFailed, msg
        end

        begin
          instrumenter.hook(probe, self)

          probe_repository.add_installed(probe)
          payload = probe_notification_builder.build_installed(probe)
          probe_notifier_worker.add_status(payload, probe: probe)
          # The probe would only be in the pending probes list if it was
          # previously attempted to be installed and the target was not loaded.
          # Always remove from pending list here because it makes the
          # API smaller and shouldn't cause any actual problems.
          probe_repository.remove_pending(probe.id)
          logger.trace { "di: installed #{probe.type} probe at #{probe.location} (#{probe.id})" }
          true
        rescue Error::DITargetNotDefined
          probe_repository.add_pending(probe)
          logger.trace { "di: could not install #{probe.type} probe at #{probe.location} (#{probe.id}) because its target is not defined, adding it to pending list" }
          false
        end
      rescue => exc
        # In "propagate all exceptions" mode we will try to instrument again.
        raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

        logger.debug { "di: error processing probe configuration: #{exc.class}: #{exc}" }
        telemetry&.report(exc, description: "Error processing probe configuration")

        payload = probe_notification_builder.build_errored(probe, exc)
        probe_notifier_worker.add_status(payload, probe: probe)

        probe_repository.add_failed(probe.id, "#{exc.class}: #{exc}")

        raise
      end

      # Removes probe with specified id. The probe could be pending or
      # installed. Does nothing if there is no probe with the specified id.
      def remove_probe(probe_id)
        probe_repository.remove_pending(probe_id)

        # Do not delete the probe from the registry here in case
        # deinstrumentation fails - though I don't know why deinstrumentation
        # would fail and how we could recover if it does.
        # I plan on tracking the number of outstanding (instrumented) probes
        # in the future, and if deinstrumentation fails I would want to
        # keep that probe as "installed" for the count, so that we can
        # investigate the situation.
        if probe = probe_repository.find_installed(probe_id)
          begin
            instrumenter.unhook(probe)
            probe_repository.remove_installed(probe_id)
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
        # TODO search more efficiently than linearly
        probe_repository.pending_probes.each do |probe_id, probe|
          if probe.method?
            # TODO move this stringification elsewhere
            if probe.type_name == cls.name
              begin
                # TODO is it OK to hook from trace point handler?
                # TODO the class is now defined, but can hooking still fail?
                instrumenter.hook(probe, self)
                probe_repository.add_installed(probe)
                probe_repository.remove_pending(probe.id)
                break
              rescue Error::DITargetNotDefined
                # This should not happen... try installing again later?
              rescue => exc
                raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                logger.debug { "di: error installing #{probe.type} probe at #{probe.location} (#{probe.id}) after class is defined: #{exc.class}: #{exc}" }
                telemetry&.report(exc, description: "Error installing probe after class is defined")

                payload = probe_notification_builder.build_errored(probe, exc)
                probe_notifier_worker.add_status(payload, probe: probe)

                probe_repository.add_failed(probe.id, "#{exc.class}: #{exc}")
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
        probe_repository.pending_probes.values.each do |probe|
          if probe.line?
            if probe.file_matches?(path)
              add_probe(probe)
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
      #
      # Snapshots are serialized to JSON immediately. If serialization fails
      # (e.g., custom serializers produce binary data), the probe is disabled
      # and an ERROR status is reported.
      def probe_executed_callback(context)
        probe = context.probe
        logger.trace { "di: executed #{probe.type} probe at #{probe.location} (#{probe.id})" }
        unless probe.emitting_notified?
          payload = probe_notification_builder.build_emitting(probe)
          probe_notifier_worker.add_status(payload, probe: probe)
          probe.emitting_notified = true
        end

        payload = probe_notification_builder.build_executed(context)

        # Serialize snapshot immediately to catch JSON encoding errors early
        begin
          serialized_snapshot = JSON.generate(payload)
          probe_notifier_worker.add_snapshot(serialized_snapshot)
        rescue JSON::GeneratorError => exc
          # Custom serializer produced data that cannot be JSON-encoded.
          # Disable the probe and report ERROR status.
          logger.debug { "di: snapshot serialization failed for #{probe.type} probe at #{probe.location} (#{probe.id}): #{exc.class}: #{exc.message}" }

          probe.disable!

          error_payload = probe_notification_builder.send(:build_status,
            probe,
            message: "Probe #{probe.id} disabled: snapshot JSON encoding failed (#{exc.class}: #{exc.message})",
            status: 'ERROR',
            exception: exc,)
          probe_notifier_worker.add_status(error_payload, probe: probe)

          telemetry&.report(exc, description: "DI snapshot JSON encoding failed for probe #{probe.id}")
        end
      end

      # Callback invoked when a probe's condition expression fails to evaluate.
      #
      # This can happen when the expression references undefined variables,
      # has type mismatches, or encounters runtime errors during evaluation.
      # The callback sends a snapshot with the error details to help users
      # debug their probe conditions.
      #
      # Rate-limited to avoid flooding the backend when conditions fail repeatedly.
      #
      # @param context [Context] The execution context containing probe and captured data
      # @param expr [String] The condition expression that failed
      # @param exc [Exception] The exception raised during condition evaluation
      def probe_condition_evaluation_failed_callback(context, expr, exc)
        probe = context.probe
        if probe.condition_evaluation_failed_rate_limiter&.allow?
          payload = probe_notification_builder.build_condition_evaluation_failed(context, expr, exc)

          # Serialize snapshot immediately to catch JSON encoding errors early
          begin
            serialized_snapshot = JSON.generate(payload)
            probe_notifier_worker.add_snapshot(serialized_snapshot)
          rescue JSON::GeneratorError => json_exc
            # Custom serializer produced data that cannot be JSON-encoded.
            # Just log the error here (probe is already in a failed state)
            logger.debug { "di: snapshot serialization failed for condition evaluation error: #{json_exc.class}: #{json_exc.message}" }
            telemetry&.report(json_exc, description: "DI snapshot JSON encoding failed for condition evaluation error")
          end
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
