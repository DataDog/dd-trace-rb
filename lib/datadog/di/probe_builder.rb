# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

require_relative "probe"
require_relative "capture_expression"
require_relative "capture_limits"
require_relative "el"

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
        "LOG_PROBE" => :log,
        "METRIC_PROBE" => :metric,
      }.freeze

      METRIC_KIND_STRINGS = { # steep:ignore IncompatibleAssignment
        "COUNT" => :count,
        "GAUGE" => :gauge,
        "HISTOGRAM" => :histogram,
        "DISTRIBUTION" => :distribution,
      }.freeze

      module_function

      CAPTURE_EXPRESSION_NAME_PATTERN = /\A[a-zA-Z0-9_?]+\z/

      # DEFAULT and a missing evaluateAt both map to exit, following the
      # Ruby log probe convention. Java and Python map DEFAULT to entry for
      # metric probes; exit is the only scope where @return and @duration
      # exist, so a DEFAULT probe degrades usefully, and the UI always
      # sends EXIT regardless.
      EVALUATE_AT_STRINGS = {
        "ENTRY" => :entry,
        "EXIT" => :exit,
        "DEFAULT" => :exit,
      }.freeze

      def build_from_remote_config(config, logger:)
        # The validations here are not yet comprehensive.
        type = config.fetch("type")
        type_symbol = PROBE_TYPES[type] or raise ArgumentError, "Unrecognized probe type: #{type}"
        cond = if cond_spec = config["when"]
          unless cond_spec["dsl"] && cond_spec["json"]
            raise ArgumentError, "Malformed condition specification for probe: #{config}"
          end
          compiled, regexps = EL::Compiler.new.compile(cond_spec["json"])
          EL::Expression.new(cond_spec["dsl"], compiled, regexps: regexps)
        end
        capture_expressions = build_capture_expressions(config["captureExpressions"])
        capture_expressions = dedup_capture_expressions(capture_expressions, config["id"], logger)
        if !!config["captureSnapshot"] && !capture_expressions.empty?
          logger.debug do
            "di: probe #{config["id"]}: captureSnapshot=true wins over captureExpressions (n=#{capture_expressions.size})"
          end
        end
        # Steep cannot infer the types of these locals across the conditional
        # multiple assignment below, so they carry explicit annotations.
        # @type var metric_kind: (:count | :gauge | :histogram | :distribution)?
        # @type var metric_name: String?
        # @type var metric_value: DI::EL::Expression?
        # @type var tags: Array[String]
        metric_kind = nil
        metric_name = nil
        metric_value = nil
        tags = []
        if type_symbol == :metric
          metric_kind, metric_name, metric_value, tags = build_metric_fields(config)
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
          template_segments: build_template_segments(config["segments"]),
          capture_snapshot: !!config["captureSnapshot"],
          max_capture_depth: config["capture"]&.[]("maxReferenceDepth"),
          max_capture_attribute_count: config["capture"]&.[]("maxFieldCount"),
          max_capture_collection_size: config["capture"]&.[]("maxCollectionSize"),
          max_capture_string_length: config["capture"]&.[]("maxLength"),
          capture_expressions: capture_expressions,
          evaluate_at: parse_evaluate_at(config["evaluateAt"], config["id"], logger),
          rate_limit: config["sampling"]&.[]("snapshotsPerSecond"),
          condition: cond,
          metric_kind: metric_kind,
          metric_name: metric_name,
          metric_value: metric_value,
          tags: tags,
        )
      rescue KeyError => exc
        raise ArgumentError, "Malformed remote configuration entry for probe: #{exc.class}: #{exc.message}: #{config}"
      end

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
          name = entry["name"]
          unless String === name && CAPTURE_EXPRESSION_NAME_PATTERN.match?(name)
            raise ArgumentError, "captureExpressions entry name missing or invalid (must match #{CAPTURE_EXPRESSION_NAME_PATTERN.inspect}): #{name.inspect}"
          end
          expr_spec = entry["expr"]
          unless Hash === expr_spec && expr_spec["dsl"] && expr_spec["json"]
            raise ArgumentError, "captureExpressions entry #{name}: missing or malformed expr"
          end
          compiled, regexps = EL::Compiler.new.compile(expr_spec["json"])
          expr = EL::Expression.new(expr_spec["dsl"], compiled, regexps: regexps)
          limits = build_capture_limits(entry["capture"])
          CaptureExpression.new(name: name, expr: expr, limits: limits)
        end
      end

      # Parses the metric fields of a METRIC_PROBE payload. The metric name
      # and tag array are validated by the Probe constructor; the kind is
      # mapped here because the payload carries it as a string, and the
      # value expression is compiled here like the condition is.
      #
      # @param config [Hash] remote configuration probe specification
      # @return [Array] metric kind, metric name, compiled value expression
      #   or nil, and tag array
      def build_metric_fields(config)
        kind = METRIC_KIND_STRINGS[config["kind"]] or raise ArgumentError, "Unknown or missing metric kind: #{config["kind"].inspect} for metric probe: #{config["id"]}"

        value = if value_spec = config["value"]
          unless value_spec["dsl"] && value_spec["json"]
            raise ArgumentError, "Malformed value specification for probe: #{config}"
          end
          compiled, regexps = EL::Compiler.new.compile(value_spec["json"])
          EL::Expression.new(value_spec["dsl"], compiled, regexps: regexps)
        end

        tags = if raw_tags = config["tags"]
          unless Array === raw_tags
            raise ArgumentError, "Metric probe #{config["id"]} tags must be an array, got: #{raw_tags.class}"
          end
          raw_tags
        else
          []
        end

        [kind, config["metricName"], value, tags]
      end

      def dedup_capture_expressions(capture_expressions, probe_id, logger)
        return capture_expressions if capture_expressions.size < 2
        by_name = {}
        capture_expressions.each do |capture_expression|
          by_name[capture_expression.name] = capture_expression
        end
        return capture_expressions if by_name.size == capture_expressions.size
        logger.debug do
          "di: probe #{probe_id}: collapsed duplicate captureExpressions names, kept last per name (#{capture_expressions.size} -> #{by_name.size})"
        end
        by_name.values
      end

      def build_capture_limits(raw)
        return nil if raw.nil?
        unless Hash === raw
          raise ArgumentError, "capture-expression entry capture must be a hash, got: #{raw.class}"
        end
        CaptureLimits.new(
          max_reference_depth: raw["maxReferenceDepth"],
          max_collection_size: raw["maxCollectionSize"],
          max_length: raw["maxLength"],
          max_field_count: raw["maxFieldCount"],
        )
      end

      def parse_evaluate_at(raw, probe_id, logger)
        return :exit if raw.nil?
        EVALUATE_AT_STRINGS[raw] || begin
          logger.debug do
            "di: probe #{probe_id}: unrecognized evaluateAt value #{raw.inspect}, defaulting to :exit"
          end
          :exit
        end
      end

      def build_template_segments(segments)
        segments&.map do |segment|
          if Hash === segment
            if str = segment["str"]
              str
            elsif ast = segment["json"]
              unless dsl = segment["dsl"]
                raise ArgumentError, "Missing dsl for json in segment: #{segment}"
              end
              compiler = EL::Compiler.new
              compiled, regexps = compiler.compile(ast)
              EL::Expression.new(dsl, compiled, regexps: regexps, redaction_identifier: compiler.redaction_identifier(ast))
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
