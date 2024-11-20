# frozen_string_literal: true

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

      # Duration is in seconds.
      def build_executed(probe,
        trace_point: nil, rv: nil, duration: nil, caller_locations: nil,
        args: nil, kwargs: nil, serialized_entry_args: nil)
        snapshot = if probe.line? && probe.capture_snapshot?
          if trace_point.nil?
            raise "Cannot create snapshot because there is no trace point"
          end
          get_local_variables(trace_point)
        end
        # TODO check how many stack frames we should be keeping/sending,
        # this should be all frames for enriched probes and no frames for
        # non-enriched probes?
        build_snapshot(probe, rv: rv, snapshot: snapshot,
          # Actual path of the instrumented file.
          path: trace_point&.path,
          duration: duration, caller_locations: caller_locations, args: args, kwargs: kwargs,
          serialized_entry_args: serialized_entry_args)
      end

      def build_snapshot(probe, rv: nil, snapshot: nil, path: nil,
        duration: nil, caller_locations: nil, args: nil, kwargs: nil,
        serialized_entry_args: nil)
        # TODO also verify that non-capturing probe does not pass
        # snapshot or vars/args into this method
        captures = if probe.capture_snapshot?
          if probe.method?
            {
              entry: {
                # standard:disable all
                arguments: if serialized_entry_args
                  serialized_entry_args
                else
                  (args || kwargs) && serializer.serialize_args(args, kwargs)
                end,
                throwable: nil,
                # standard:enable all
              },
              return: {
                arguments: {
                  "@return": serializer.serialize_value(rv),
                },
                throwable: nil,
              },
            }
          elsif probe.line?
            {
              lines: snapshot && {
                probe.line_no => {locals: serializer.serialize_vars(snapshot)},
              },
            }
          end
        end

        location = if probe.line?
          {
            file: path,
            lines: [probe.line_no],
          }
        elsif probe.method?
          {
            method: probe.method_name,
            type: probe.type_name,
          }
        end

        stack = if caller_locations
          format_caller_locations(caller_locations)
        end

        timestamp = timestamp_now
        {
          service: settings.service,
          "debugger.snapshot": {
            id: SecureRandom.uuid,
            timestamp: timestamp,
            evaluationErrors: [],
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
          # In python tracer duration is under debugger.snapshot,
          # but UI appears to expect it here at top level.
          duration: duration ? (duration * 10**9).to_i : 0,
          host: nil,
          logger: {
            name: probe.file,
            method: probe.method_name || 'no_method',
            thread_name: Thread.current.name,
            # Dynamic instrumentation currently does not need thread_id for
            # anything. It can be sent if a customer requests it at which point
            # we can also determine which thread identifier to send
            # (Thread#native_thread_id or something else).
            thread_id: nil,
            version: 2,
          },
          # TODO add tests that the trace/span id is correctly propagated
          "dd.trace_id": Datadog::Tracing.active_trace&.id&.to_s,
          "dd.span_id": Datadog::Tracing.active_span&.id&.to_s,
          ddsource: 'dd_debugger',
          message: probe.template && evaluate_template(probe.template,
            duration: duration ? duration * 1000 : 0),
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

      def evaluate_template(template, **vars)
        message = template.dup
        vars.each do |key, value|
          message.gsub!("{@#{key}}", value.to_s)
        end
        message
      end

      def timestamp_now
        (Time.now.to_f * 1000).to_i
      end

      def get_local_variables(trace_point)
        # binding appears to be constructed on access, therefore
        # 1) we should attempt to cache it and
        # 2) we should not call +binding+ until we actually need variable values.
        binding = trace_point.binding

        # steep hack - should never happen
        return {} unless binding

        binding.local_variables.each_with_object({}) do |name, map|
          value = binding.local_variable_get(name)
          map[name] = value
        end
      end
    end
  end
end
