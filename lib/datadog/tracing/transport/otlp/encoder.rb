# frozen_string_literal: true

require_relative '../../../core/utils/base64_codec'
require_relative '../../utils'
require_relative '../../metadata/ext'

module Datadog
  module Tracing
    module Transport
      module OTLP
        # Encodes Datadog traces into the OTLP ExportTraceServiceRequest JSON (http/json) shape.
        #
        # The output mirrors dd-trace-js's pure implementation and libdatadog, producing
        # lowerCamelCase JSON:
        #   { resourceSpans: [ { resource: {...}, scopeSpans: [ { scope: {...}, spans: [...] } ] } ] }
        #
        # @see https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding
        class Encoder
          # OTLP SpanKind enum values (trace.proto Span.SpanKind).
          SPAN_KIND_UNSPECIFIED = 0
          SPAN_KIND_INTERNAL = 1
          SPAN_KIND_SERVER = 2
          SPAN_KIND_CLIENT = 3
          SPAN_KIND_PRODUCER = 4
          SPAN_KIND_CONSUMER = 5

          # OTLP StatusCode enum values (trace.proto Status.StatusCode).
          STATUS_CODE_UNSET = 0
          STATUS_CODE_ERROR = 2

          # Maps a DD `span.kind` meta value to an OTLP SpanKind.
          SPAN_KIND_BY_META = {
            'internal' => SPAN_KIND_INTERNAL,
            'server' => SPAN_KIND_SERVER,
            'client' => SPAN_KIND_CLIENT,
            'producer' => SPAN_KIND_PRODUCER,
            'consumer' => SPAN_KIND_CONSUMER,
          }.freeze

          # Maps a DD span `type` to an OTLP SpanKind when `span.kind` meta is absent.
          SPAN_KIND_BY_TYPE = {
            'web' => SPAN_KIND_SERVER,
            'http' => SPAN_KIND_SERVER,
            'server' => SPAN_KIND_SERVER,
            'client' => SPAN_KIND_CLIENT,
            'producer' => SPAN_KIND_PRODUCER,
            'consumer' => SPAN_KIND_CONSUMER,
          }.freeze

          # Largest/smallest values representable as a signed 64-bit integer; metrics outside this
          # range are encoded as `doubleValue` rather than `intValue`.
          MIN_INT64 = -9_223_372_036_854_775_808
          MAX_INT64 = 9_223_372_036_854_775_807

          INSTRUMENTATION_SCOPE_NAME = 'dd-trace-rb'

          SPAN_KIND_META = Tracing::Metadata::Ext::TAG_KIND
          ERROR_MSG_META = Tracing::Metadata::Ext::Errors::TAG_MSG
          TID_META = Tracing::Metadata::Ext::Distributed::TAG_TID

          # Meta keys that are promoted to dedicated OTLP fields and must not be duplicated as
          # attributes: `span.kind` maps to the OTLP span kind, `_dd.p.tid` supplies the upper 64
          # bits of the trace id (mirrors dd-trace-js's exclusion set).
          EXCLUDED_META_KEYS = [SPAN_KIND_META, TID_META].freeze

          # @param resource_attributes [Array<Hash>] OTLP KeyValue resource attributes
          # @param scope_version [String,nil] instrumentation scope version (gem version)
          # @param default_service [String,nil] default service; per-span `service.name` is emitted
          #   only when the span's service differs from this value
          def initialize(resource_attributes:, scope_version: nil, default_service: nil)
            @resource_attributes = resource_attributes
            @scope_version = scope_version
            @default_service = default_service
          end

          # Encodes a single trace into the OTLP ExportTraceServiceRequest JSON String.
          #
          # @param trace [Datadog::Tracing::TraceSegment]
          # @return [String]
          def encode(trace)
            JSON.dump(payload(trace))
          end

          # Builds the OTLP request Hash for a trace.
          #
          # @param trace [Datadog::Tracing::TraceSegment]
          # @return [Hash]
          def payload(trace)
            spans = trace.spans

            # `_dd.p.tid` (upper 64 bits of a 128-bit trace id) lives on the first-in-chunk span only.
            trace_id_high = nil
            spans.each do |span|
              tid = span.meta[TID_META]
              if tid && !tid.empty?
                trace_id_high = tid
                break
              end
            end

            {
              resourceSpans: [
                {
                  resource: {attributes: @resource_attributes},
                  scopeSpans: [
                    {
                      scope: {name: INSTRUMENTATION_SCOPE_NAME, version: @scope_version},
                      spans: spans.map { |span| encode_span(span, trace_id_high) },
                    },
                  ],
                },
              ],
            }
          end

          private

          def encode_span(span, trace_id_high)
            otlp_span = {
              traceId: trace_id_hex(span.trace_id, trace_id_high),
              spanId: id_hex(span.id),
              name: span.resource.to_s,
              kind: span_kind(span),
              startTimeUnixNano: start_time_nano(span),
              endTimeUnixNano: end_time_nano(span),
              attributes: attributes(span),
              status: status(span),
            }

            parent_id = span.parent_id
            otlp_span[:parentSpanId] = id_hex(parent_id) if parent_id && parent_id != 0

            unless span.links.empty?
              otlp_span[:links] = span.links.map { |link| encode_link(link) }
            end

            unless span.events.empty?
              otlp_span[:events] = span.events.map { |event| encode_event(event) }
            end

            otlp_span
          end

          # Builds the OTLP KeyValue attribute list from DD span fields, meta, metrics and meta_struct.
          def attributes(span)
            attrs = []

            attrs << string_attribute('resource.name', span.resource) unless span.resource.to_s.empty?
            attrs << string_attribute('operation.name', span.name) unless span.name.to_s.empty?

            service = span.service
            if service && !service.empty? && service != @default_service
              attrs << string_attribute('service.name', service)
            end

            attrs << string_attribute('span.type', span.type) unless span.type.to_s.empty?

            span.meta.each do |key, value|
              next if EXCLUDED_META_KEYS.include?(key)

              attrs << {key: key, value: {stringValue: value.to_s}}
            end

            span.metrics.each do |key, value|
              attrs << {key: key, value: numeric_value(value)}
            end

            meta_struct = span.metastruct.to_h
            meta_struct.each do |key, value|
              bytes = value.is_a?(String) ? value : JSON.dump(value)
              attrs << {key: key, value: {bytesValue: Core::Utils::Base64Codec.strict_encode64(bytes)}}
            end

            attrs
          end

          def encode_link(link)
            hash = link.to_hash
            trace_id_low = hash[:trace_id] || 0
            trace_id_high = hash[:trace_id_high]
            trace_id = trace_id_high ? Tracing::Utils::TraceId.concatenate(trace_id_high, trace_id_low) : trace_id_low

            otlp_link = {
              traceId: format('%032x', trace_id),
              spanId: id_hex(hash[:span_id] || 0),
            }

            attributes = hash[:attributes]
            otlp_link[:attributes] = attributes.map { |k, v| {key: k, value: {stringValue: v.to_s}} } if attributes

            trace_state = hash[:tracestate]
            otlp_link[:traceState] = trace_state if trace_state && !trace_state.empty?

            flags = hash[:flags]
            otlp_link[:flags] = flags if flags

            otlp_link
          end

          def encode_event(event)
            otlp_event = {
              timeUnixNano: event.time_unix_nano,
              name: event.name.to_s,
            }

            attributes = event.attributes
            unless attributes.empty?
              otlp_event[:attributes] = attributes.map { |k, v| {key: k.to_s, value: any_value(v)} }
            end

            otlp_event
          end

          # Maps a value to an OTLP AnyValue (used for span event attributes, which may be arrays).
          def any_value(value)
            case value
            when String
              {stringValue: value}
            when Integer
              integer_value(value)
            when Float
              {doubleValue: value}
            when true, false
              {boolValue: value}
            when Array
              {arrayValue: {values: value.map { |v| any_value(v) }}}
            else
              {stringValue: value.to_s}
            end
          end

          # Maps a DD metric (always numeric) to an OTLP int/double value.
          def numeric_value(value)
            if value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.to_i)
              integer_value(value.to_i)
            else
              {doubleValue: value}
            end
          end

          # OTLP http/json encodes 64-bit integers as decimal strings.
          def integer_value(value)
            if value >= MIN_INT64 && value <= MAX_INT64
              {intValue: value.to_s}
            else
              {doubleValue: value.to_f}
            end
          end

          def span_kind(span)
            kind = span.meta[SPAN_KIND_META]
            return SPAN_KIND_BY_META.fetch(kind, SPAN_KIND_UNSPECIFIED) if kind && !kind.empty?

            type = span.type
            return SPAN_KIND_BY_TYPE.fetch(type, SPAN_KIND_INTERNAL) if type && !type.empty?

            SPAN_KIND_UNSPECIFIED
          end

          def status(span)
            if span.status != 0
              {code: STATUS_CODE_ERROR, message: span.meta[ERROR_MSG_META].to_s}
            else
              {code: STATUS_CODE_UNSET}
            end
          end

          # 128-bit trace id as 32 lowercase hex chars: low 64 bits from the span trace id,
          # high 64 bits from the `_dd.p.tid` meta value (0 if absent).
          def trace_id_hex(trace_id, trace_id_high)
            low = Tracing::Utils::TraceId.to_low_order(trace_id)
            high = trace_id_high ? trace_id_high.to_i(16) : Tracing::Utils::TraceId.to_high_order(trace_id)
            format('%016x%016x', high, low)
          end

          # 64-bit id as 16 lowercase hex chars.
          def id_hex(id)
            format('%016x', id)
          end

          def start_time_nano(span)
            start_time = span.start_time
            return 0 unless start_time

            start_time.to_i * 1_000_000_000 + start_time.nsec
          end

          def end_time_nano(span)
            start = start_time_nano(span)
            duration = span.duration
            return start unless duration

            start + (duration * 1e9).to_i
          end

          def string_attribute(key, value)
            {key: key, value: {stringValue: value.to_s}}
          end
        end
      end
    end
  end
end
