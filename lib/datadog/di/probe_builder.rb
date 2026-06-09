# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

require_relative "probe"
require_relative "capture_expression"
require_relative "capture_limits"
require_relative 'el'

module Datadog
  module DI
    # Creates Probe instances from remote configuration payloads.
    #
    # Due to the dynamic instrumentation product evolving over time,
    # it is possible that the payload corresponds to a type of probe that the
    # current version of the library does not handle.
    # For now ArgumentError is raised in such cases (by ProbeBuilder or
    # Probe constructor), since generally DI is meant to rescue all exceptions
    # internally and not propagate any exceptions to applications.
    # A dedicated exception could be added in the future if there is a use case
    # for it.
    #
    # @api private
    module ProbeBuilder
      # Steep: https://github.com/soutaro/steep/issues/363
      PROBE_TYPES = { # steep:ignore IncompatibleAssignment
        'LOG_PROBE' => :log,
      }.freeze

      module_function

      # Backend JSON schema constraint on capture-expression names:
      # remote-config/apps/rc-schema-validation/schemas/live-debugging.json
      # in DataDog/dd-go declares pattern "^[a-zA-Z0-9_?]+$".
      CAPTURE_EXPRESSION_NAME_PATTERN = /\A[a-zA-Z0-9_?]+\z/

      # Permitted values for the RC payload's `evaluateAt` field. Backend
      # schema (DataDog/dd-go live-debugging.json) also accepts "DEFAULT"
      # for Java compatibility; we normalize that to :exit at parse time to
      # match the libdatadog default.
      EVALUATE_AT_STRINGS = {
        "ENTRY" => :entry,
        "EXIT" => :exit,
        "DEFAULT" => :exit,
      }.freeze

      def build_from_remote_config(config)
        # The validations here are not yet comprehensive.
        type = config.fetch('type')
        type_symbol = PROBE_TYPES[type] or raise ArgumentError, "Unrecognized probe type: #{type}"
        cond = if cond_spec = config['when']
          unless cond_spec['dsl'] && cond_spec['json']
            raise ArgumentError, "Malformed condition specification for probe: #{config}"
          end
          compiled = EL::Compiler.new.compile(cond_spec['json'])
          EL::Expression.new(cond_spec['dsl'], compiled)
        end
        capture_expressions = build_capture_expressions(config['captureExpressions'])
        if !!config["captureSnapshot"] && !capture_expressions.empty?
          # When both captureSnapshot and captureExpressions are set on the
          # same probe, the runtime emits the snapshot block and silently
          # drops capture-expression values (snapshot wins), matching
          # Python/Java/Go DI. Logged at debug to make the choice observable
          # without spamming operator logs.
          Datadog.logger.debug do
            "di: probe #{config["id"]}: captureSnapshot=true wins over captureExpressions (n=#{capture_expressions.size})"
          end
        end
        Probe.new(
          id: config.fetch("id"),
          type: type_symbol,
          file: config["where"]&.[]("sourceFile"),
          # Sometimes lines are sometimes received as an array of nil
          # for some reason.
          line_no: config["where"]&.[]("lines")&.compact&.map(&:to_i)&.first,
          type_name: config["where"]&.[]("typeName"),
          method_name: config["where"]&.[]("methodName"),
          # We should not be using the template for anything - we instead
          # use +segments+ - but keep the template for debugging.
          template: config["template"],
          template_segments: build_template_segments(config['segments']),
          capture_snapshot: !!config["captureSnapshot"],
          max_capture_depth: config["capture"]&.[]("maxReferenceDepth"),
          max_capture_attribute_count: config["capture"]&.[]("maxFieldCount"),
          max_capture_collection_size: config["capture"]&.[]("maxCollectionSize"),
          max_capture_string_length: config["capture"]&.[]("maxLength"),
          capture_expressions: capture_expressions,
          evaluate_at: parse_evaluate_at(config["evaluateAt"], config["id"]),
          rate_limit: config["sampling"]&.[]("snapshotsPerSecond"),
          condition: cond,
        )
      rescue KeyError => exc
        raise ArgumentError, "Malformed remote configuration entry for probe: #{exc.class}: #{exc.message}: #{config}"
      end

      # Parses the `captureExpressions` block of a remote-config probe payload
      # into compiled CaptureExpression instances.
      #
      # @param raw [Array<Hash>, nil] raw `captureExpressions` value from the
      #   remote-config payload. nil is treated as "no expressions" (returns []).
      # @return [Array<Datadog::DI::CaptureExpression>] one per entry; empty
      #   array when raw is nil or empty.
      # @raise [ArgumentError] when raw is non-nil and not an Array, when any
      #   entry is not a Hash, when an entry's name is missing or fails the
      #   CAPTURE_EXPRESSION_NAME_PATTERN charset check, or when the `expr`
      #   field is missing/malformed.
      def build_capture_expressions(raw)
        return [] if raw.nil?
        unless Array === raw
          raise ArgumentError, "captureExpressions must be an array, got: #{raw.class}"
        end
        return [] if raw.empty?
        raw.map do |entry|
          unless Hash === entry
            raise ArgumentError, "captureExpressions entry must be a hash, got: #{entry.class}"
          end
          name = entry['name']
          unless String === name && CAPTURE_EXPRESSION_NAME_PATTERN.match?(name)
            raise ArgumentError, "captureExpressions entry name missing or invalid (must match #{CAPTURE_EXPRESSION_NAME_PATTERN.inspect}): #{name.inspect}"
          end
          expr_spec = entry['expr']
          unless Hash === expr_spec && expr_spec['dsl'] && expr_spec['json']
            raise ArgumentError, "captureExpressions entry #{name}: missing or malformed expr"
          end
          compiled = EL::Compiler.new.compile(expr_spec['json'])
          expr = EL::Expression.new(expr_spec['dsl'], compiled)
          limits = build_capture_limits(entry['capture'])
          CaptureExpression.new(name: name, expr: expr, limits: limits)
        end
      end

      # Parses a per-expression `capture` block of a remote-config probe payload
      # into a CaptureLimits instance.
      #
      # @param raw [Hash, nil] raw per-expression `capture` value. nil means
      #   "no per-expression overrides" (returns nil).
      # @return [Datadog::DI::CaptureLimits, nil] CaptureLimits when raw is a
      #   Hash; nil when raw is nil.
      # @raise [ArgumentError] when raw is non-nil and not a Hash.
      def build_capture_limits(raw)
        return nil if raw.nil?
        unless Hash === raw
          raise ArgumentError, "capture-expression entry capture must be a hash, got: #{raw.class}"
        end
        CaptureLimits.new(
          max_reference_depth: raw['maxReferenceDepth'],
          max_collection_size: raw['maxCollectionSize'],
          max_length: raw['maxLength'],
          max_field_count: raw['maxFieldCount'],
        )
      end

      # Parses the RC payload's `evaluateAt` string into the
      # +Datadog::DI::Probe+ symbol form. "ENTRY" → :entry, "EXIT" → :exit,
      # "DEFAULT" → :exit (Java sends this; libdatadog also treats it as
      # Exit). Absent or unrecognized values coerce to :exit and emit a
      # debug log; the runtime never raises on an unknown evaluateAt because
      # such payloads should still install as conventional EXIT-timed probes.
      #
      # @param raw [String, nil] raw `evaluateAt` value from the RC payload.
      # @param probe_id [String, nil] probe id for the diagnostic log line.
      # @return [Symbol] :entry or :exit.
      def parse_evaluate_at(raw, probe_id)
        return :exit if raw.nil?
        EVALUATE_AT_STRINGS[raw] || begin
          Datadog.logger.debug do
            "di: probe #{probe_id}: unrecognized evaluateAt value #{raw.inspect}, defaulting to :exit"
          end
          :exit
        end
      end

      def build_template_segments(segments)
        segments&.map do |segment|
          if Hash === segment
            if str = segment['str']
              str
            elsif ast = segment['json']
              unless dsl = segment['dsl']
                raise ArgumentError, "Missing dsl for json in segment: #{segment}"
              end
              compiled = EL::Compiler.new.compile(ast)
              EL::Expression.new(dsl, compiled)
            else
              # TODO report to telemetry?
            end
          else
            # TODO report to telemetry?
          end
        end&.compact
      end
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
