# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # Amazon Resource Name. Fields an ARN leaves empty are `nil`.
        #
        # @see https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html
        class Arn
          PREFIX = "arn:"
          SEGMENT_COUNT = 6
          PARTITION_FORMAT = /\Aaws(?:-[a-z0-9]+)*\z/
          REGION_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*-\d+\z/
          ACCOUNT_ID_FORMAT = /\A\d{12}\z/
          RESOURCE_SEPARATOR = %r{[:/]}

          attr_reader :partition, :service, :region, :account_id, :resource, :resource_segments

          # `String#start_with?` raises on a non-ASCII-compatible encoding and
          # `Regexp#match?` raises on invalid bytes.
          def self.scannable?(value)
            value.is_a?(::String) && value.encoding.ascii_compatible? && value.valid_encoding?
          end

          # Compares bytes, so it is safe on any encoding.
          def self.arn_like?(value)
            return false unless value.is_a?(::String)

            value.byteslice(0, PREFIX.bytesize) == PREFIX
          end

          def self.parse(value)
            return nil unless scannable?(value)
            return nil unless arn_like?(value)

            segments = value.split(":", SEGMENT_COUNT)
            return nil unless segments.length == SEGMENT_COUNT

            partition = segments[1]
            service = segments[2]
            region = segments[3]
            account_id = segments[4]
            resource = segments[5]
            return nil if service.empty? || resource.empty?
            return nil unless PARTITION_FORMAT.match?(partition)
            return nil unless region.empty? || REGION_FORMAT.match?(region)
            return nil unless account_id.empty? || ACCOUNT_ID_FORMAT.match?(account_id)

            new(
              partition: partition,
              service: service,
              region: region.empty? ? nil : region,
              account_id: account_id.empty? ? nil : account_id,
              resource: resource,
            )
          end

          def initialize(partition:, service:, region:, account_id:, resource:)
            @partition = partition
            @service = service
            @region = region
            @account_id = account_id
            @resource = resource
            # `-1` keeps trailing empty segments, so `table/MyTable/` is not `table/MyTable`.
            @resource_segments = resource.split(RESOURCE_SEPARATOR, -1)
          end

          # The `MyTable` of `table/MyTable`.
          def typed_resource_id(service_name, resource_types, segments: nil)
            return nil unless service == service_name
            return nil unless resource_types.include?(resource_segments[0])
            return nil if segments && resource_segments.length != segments

            id = resource_segments[1]
            return nil if id.nil? || id.empty?

            id
          end

          # The `my-topic` of an SNS topic ARN.
          def bare_resource_id(service_name)
            return nil unless service == service_name
            return nil unless resource_segments.length == 1

            resource
          end
        end
      end
    end
  end
end
