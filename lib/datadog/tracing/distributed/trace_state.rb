# frozen_string_literal: true

require_relative "../../core/utils"
require_relative "trace_state/ext"
require_relative "trace_state/datadog"
require_relative "trace_state/open_telemetry"

module Datadog
  module Tracing
    module Distributed
      # Parsed vendor state from a W3C `tracestate` header.
      # @api private
      class TraceState
        class << self
          def from_digest(digest, propagate_sampling: true)
            new(
              tracestate: digest.trace_state,
              datadog: Datadog.from_digest(digest),
              open_telemetry: OpenTelemetry.from_digest(digest, propagate_sampling: propagate_sampling),
            )
          end

          # Parses owned members while retaining other vendors unchanged.
          def extract(tracestate)
            vendors = split(tracestate) || []
            datadog_index = vendors.index { |vendor| vendor.start_with?("dd=") }
            datadog_value = vendors.delete_at(datadog_index).delete_prefix("dd=") if datadog_index
            otel_index = vendors.index { |vendor| vendor.start_with?("ot=") }
            otel_value = vendors.delete_at(otel_index).delete_prefix("ot=") if otel_index

            new(
              tracestate: vendors.empty? ? nil : vendors.join(","),
              datadog: Datadog.from_tracestate_member(datadog_value),
              open_telemetry: OpenTelemetry.from_tracestate_member(otel_value),
            )
          end

          # Partial members must not be propagated, but complete members within the limits are retained.
          def split(tracestate)
            return if tracestate.nil? || tracestate.empty?

            remove_last_vendor = false
            if tracestate.bytesize > Ext::TRACESTATE_MAX_SIZE_LIMIT
              remove_last_vendor = tracestate.byteslice(Ext::TRACESTATE_MAX_SIZE_LIMIT, 1) != ","
              tracestate = tracestate.byteslice(0, Ext::TRACESTATE_MAX_SIZE_LIMIT + 1) #: String
              tracestate = tracestate.chop
            end

            tracestate = ::Datadog::Core::Utils.utf8_encode(tracestate, placeholder: nil)
            return unless tracestate

            vendors = tracestate.split(",", Ext::TRACESTATE_MAX_LIST_VENDORS + 1)
            vendors.pop if vendors.length > Ext::TRACESTATE_MAX_LIST_VENDORS || remove_last_vendor
            vendors.each(&:strip!)
            vendors.pop while vendors.last == ""
            vendors
          end
        end

        attr_reader :tracestate, :datadog, :open_telemetry

        def initialize(tracestate: nil, datadog: nil, open_telemetry: nil)
          @tracestate = tracestate
          @datadog = datadog || Datadog.new
          @open_telemetry = open_telemetry || OpenTelemetry.new
        end

        # Builds the complete header from parsed Datadog and OpenTelemetry state.
        def build
          leading_vendors = select_leading_vendors
          vendors = TraceState.split(tracestate)

          if leading_vendors.empty?
            return unless vendors && !vendors.empty?

            return vendors.join(",")
          end

          vendors&.reject! { |vendor| vendor.start_with?("dd=", "ot=") }

          tracestate = leading_vendors.join(",")
          if vendors && !vendors.empty?
            vendors.first(Ext::TRACESTATE_MAX_LIST_VENDORS - leading_vendors.size).each do |vendor|
              break if tracestate.bytesize + vendor.bytesize + 1 > Ext::TRACESTATE_MAX_SIZE_LIMIT

              tracestate << "," << vendor
            end
          end

          tracestate
        end

        private

        def select_leading_vendors
          leading_vendors = []
          add_leading_vendor(leading_vendors, datadog)
          add_leading_vendor(leading_vendors, open_telemetry)

          leading_vendors
        end

        def add_leading_vendor(leading_vendors, state)
          vendor = state.build
          return if vendor.empty?

          combined_size = leading_vendors.sum { |current| current.bytesize } +
            leading_vendors.size + vendor.bytesize
          leading_vendors << vendor if combined_size <= Ext::TRACESTATE_MAX_SIZE_LIMIT
        end
      end
    end
  end
end
