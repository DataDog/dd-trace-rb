# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

module Datadog
  module DI
    # Builds probe status notification and snapshot payloads.
    #
    # @api private
    class ProbeNotificationBuilder
      def initialize(settings, serializer)
        @settings = settings
        @serializer = serializer
      end

      attr_reader :settings
      attr_reader :serializer

      def build_received(probe)
        build_status(probe,
          message: "Probe #{probe.id} has been received correctly",
          status: 'RECEIVED',)
      end

      def build_installed(probe)
        build_status(probe,
          message: "Probe #{probe.id} has been instrumented correctly",
          status: 'INSTALLED',)
      end

      def build_emitting(probe)
        build_status(probe,
          message: "Probe #{probe.id} is emitting",
          status: 'EMITTING',)
      end

      def build_errored(probe, exc)
        build_status(probe,
          message: "Instrumentation for probe #{probe.id} failed: #{exc}",
          status: 'ERROR',)
      end

      # Duration is in seconds.
      # path is the actual path of the instrumented file.
      def build_executed(context)
        build_snapshot(context)
      end

      NANOSECONDS = 10**9
      MILLISECONDS = 1000

      def build_snapshot(context)
        probe = context.probe

        if probe.capture_snapshot? && !context.target_self
          raise ArgumentError, "Asked to build snapshot with snapshot capture but target_self is nil"
        end

        # TODO also verify that non-capturing probe does not pass
        # snapshot or vars/args into this method
        captures = if probe.capture_snapshot?
          if probe.method?
            return_arguments = {
              "@return": serializer.serialize_value(context.return_value,
                depth: probe.max_capture_depth || settings.dynamic_instrumentation.max_capture_depth,
                attribute_count: probe.max_capture_attribute_count || settings.dynamic_instrumentation.max_capture_attribute_count),
              self: serializer.serialize_value(context.target_self),
            }
            {
              entry: {
                arguments: context.serialized_entry_args,
              },
              return: {
                arguments: return_arguments,
                throwable: nil,
              },
            }
          elsif probe.line?
            {
              lines: (locals = context.serialized_locals) && {
                probe.line_no => {
                  locals: locals,
                  arguments: {self: serializer.serialize_value(context.target_self)},
                },
              },
            }
          end
        end

        message = nil
        evaluation_errors = []
        if segments = probe.template_segments
          message, evaluation_errors = evaluate_template(segments, context)
        end
        build_snapshot_base(context,
          evaluation_errors: evaluation_errors, message: message,
          captures: captures)
      end

      def build_condition_evaluation_failed(context, expression, exception)
        error = {
          message: "#{exception.class}: #{exception}",
          expr: expression.dsl_expr,
        }
        build_snapshot_base(context, evaluation_errors: [error])
      end

      private

      def build_snapshot_base(context, evaluation_errors: [], captures: nil, message: nil)
        probe = context.probe

        timestamp = timestamp_now
        duration = context.duration

        location = if probe.line?
          {
            file: context.path,
            # Line numbers are required to be strings by the
            # system tests schema.
            # Backend I think accepts them also as integers, but some
            # other languages send strings and we decided to require
            # strings for everyone.
            lines: [probe.line_no.to_s],
          }
        elsif probe.method?
          {
            method: probe.method_name,
            type: probe.type_name,
          }
        end

        stack = if caller_locations = context.caller_locations
          format_caller_locations(caller_locations)
        end

        {
          service: settings.service,
          debugger: {
            type: 'snapshot',
            # Product can have three values: di, ld, er.
            # We do not currently implement exception replay.
            # There is currently no specification, and no consensus, for
            # when product should be di (dynamic instrumentation) and when
            # it should be ld (live debugger). I thought the backend was
            # supposed to provide this in probe specification via remote
            # config, but apparently this is not the case and the expectation
            # is that the library figures out the product via heuristics,
            # except there is currently no consensus on said heuristics.
            # .NET always sends ld, other languages send nothing at the moment.
            # Don't send anything for the time being.
            #product: 'di/ld',
            snapshot: {
              id: SecureRandom.uuid,
              timestamp: timestamp,
              evaluationErrors: evaluation_errors,
              probe: {
                id: probe.id,
                version: 0,
                location: location,
              },
              language: 'ruby',
              # TODO add test coverage for callers being nil
              stack: stack,
              captures: captures,
            },
          },
          # In python tracer duration is under debugger.snapshot,
          # but UI appears to expect it here at top level.
          duration: duration ? (duration * NANOSECONDS).to_i : 0,
          host: nil,
          logger: {
            name: probe.file,
            method: probe.method_name,
            thread_name: Thread.current.name,
            # Dynamic instrumentation currently does not need thread_id for
            # anything. It can be sent if a customer requests it at which point
            # we can also determine which thread identifier to send
            # (Thread#native_thread_id or something else).
            thread_id: nil,
            version: 2,
          },
          # TODO add tests that the trace/span id is correctly propagated
          "dd.trace_id": active_trace&.id&.to_s,
          "dd.span_id": active_span&.id&.to_s,
          ddsource: 'dd_debugger',
          message: message,
          timestamp: timestamp,
        }
      end

      def build_status(probe, message:, status:)
        {
          service: settings.service,
          timestamp: timestamp_now,
          message: message,
          ddsource: 'dd_debugger',
          debugger: {
            diagnostics: {
              probeId: probe.id,
              probeVersion: 0,
              runtimeId: Core::Environment::Identity.id,
              parentId: nil,
              status: status,
            },
          },
        }
      end

      def format_caller_locations(caller_locations)
        caller_locations.map do |loc|
          {fileName: loc.path, function: loc.label, lineNumber: loc.lineno}
        end
      end

      def evaluate_template(template_segments, context)
        evaluation_errors = []
        message = template_segments.map do |segment|
          case segment
          when String
            segment
          when EL::Expression
            serializer.serialize_value_for_message(segment.evaluate(context))
          else
            raise ArgumentError, "Invalid template segment type: #{segment}"
          end
        rescue => exc
          evaluation_errors << {
            message: "#{exc.class}: #{exc}",
            expr: segment.dsl_expr,
          }
          '[evaluation error]'
        end.join
        [message, evaluation_errors]
      end

      def timestamp_now
        (Core::Utils::Time.now.to_f * MILLISECONDS).to_i
      end

      def active_trace
        if defined?(Datadog::Tracing)
          Datadog::Tracing.active_trace
        end
      end

      def active_span
        if defined?(Datadog::Tracing)
          Datadog::Tracing.active_span
        end
      end
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
