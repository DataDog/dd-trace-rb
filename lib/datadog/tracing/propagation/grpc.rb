# typed: false

require_relative '../distributed/metadata/datadog'
require_relative '../distributed/metadata/b3'
require_relative '../distributed/metadata/b3_single'

require_relative '../span'
require_relative '../trace_digest'
require_relative '../trace_operation'

module Datadog
  module Tracing
    module Propagation
      # opentracing.io compliant methods for distributing trace headers
      # between two or more distributed services. Note this is very close
      # to the Propagation::HTTP; the key difference is the way gRPC handles
      # header information (called "metadata") as it operates over HTTP2
      module GRPC
        PROPAGATION_STYLES = {
          Configuration::Ext::Distributed::PROPAGATION_STYLE_B3 => Distributed::Metadata::B3,
          Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER => Distributed::Metadata::B3Single,
          Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG => Distributed::Metadata::Datadog
        }.freeze

        def self.inject!(digest, metadata)
          return if digest.nil?

          digest = digest.to_digest if digest.is_a?(TraceOperation)

          Datadog.configuration.tracing.distributed_tracing.propagation_inject_style.each do |style|
            propagator = PROPAGATION_STYLES[style]
            begin
              propagator.inject!(digest, metadata) unless propagator.nil?
            rescue => e
              Datadog.logger.error(
                'Error injecting propagated trace headers into the environment. ' \
                "Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end
          end
        end

        def self.extract(metadata)
          trace_digest = nil
          dd_trace_digest = nil

          Datadog.configuration.tracing.distributed_tracing.propagation_extract_style.each do |style|
            propagator = PROPAGATION_STYLES[style]

            next if propagator.nil?

            # Extract trace headers
            begin
              extracted_trace_digest = propagator.extract(metadata)
            rescue => e
              Datadog.logger.error(
                'Error extracting propagated trace headers from the environment. ' \
                "Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end

            # Skip this style if no valid headers were found
            next if extracted_trace_digest.nil?

            # Keep track of the Datadog extract trace headers, we want to return
            #   this one if we have one
            if extracted_trace_digest && style == Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG
              dd_trace_digest = extracted_trace_digest
            end

            # No previously extracted trace headers, use the one we just extracted
            if trace_digest.nil?
              trace_digest = extracted_trace_digest
            else
              unless trace_digest.trace_id == extracted_trace_digest.trace_id \
                      && trace_digest.span_id == extracted_trace_digest.span_id
                # Return an empty/new trace headers if we have a mismatch in values extracted
                msg = "#{trace_digest.trace_id} != #{extracted_trace_digest.trace_id} && " \
                      "#{trace_digest.span_id} != #{extracted_trace_digest.span_id}"
                Datadog.logger.debug(
                  "Cannot extract trace headers from HTTP: extracted trace headers differ, #{msg}"
                )
                # DEV: This will return from `self.extract` not this `each` block
                return TraceDigest.new
              end
            end
          end

          # Return the extracted trace headers if we found one or else a new empty trace headers
          # Always return the Datadog trace headers if one exists since it has more
          #   information than the B3 headers e.g. origin, expanded priority
          #   sampling values, etc
          dd_trace_digest || trace_digest || nil
        end
      end
    end
  end
end
