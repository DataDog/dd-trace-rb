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

          attr_reader :partition, :service, :region, :account_id, :resource

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
            return nil unless value.is_a?(::String) && value.encoding.ascii_compatible?
            return nil unless value.start_with?(PREFIX) && value.valid_encoding?

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
          end

          # The `name` capture of `format` matched against the whole resource.
          # Each service has its own resource grammar, so a shared separator
          # split would accept shapes like `table:MyTable` that AWS rejects.
          # Every resource read this way lives in one Region and one account.
          def resource_name(service_name, format)
            return nil unless service == service_name && region && account_id

            format.match(resource)&.[](:name)
          end
        end
      end
    end
  end
end
