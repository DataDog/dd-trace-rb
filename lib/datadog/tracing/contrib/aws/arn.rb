# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # A strict, non-throwing parser for Amazon Resource Names. {.parse}
        # validates the whole structure and answers `nil` for anything
        # malformed. A field the ARN omits stays `nil` rather than guessed.
        #
        # @see https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html
        class Arn
          PREFIX = "arn:"

          # `arn:<partition>:<service>:<region>:<account-id>:<resource>`
          SEGMENT_COUNT = 6

          # `aws`, plus `aws-cn`, `aws-us-gov` and the ISO partitions.
          PARTITION_FORMAT = /\Aaws(?:-[a-z0-9]+)*\z/

          # A lowercase, hyphen-separated Region code ending in a digit
          # (`us-east-1`, `cn-north-1`, `us-gov-west-1`, `us-iso-east-1`).
          REGION_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*-\d+\z/

          ACCOUNT_ID_FORMAT = /\A\d{12}\z/

          # A resource is either a bare id, or a type and id joined by `/` or
          # `:`. The delimiters are interchangeable for the resources handled
          # here, none of which contain either character.
          RESOURCE_SEPARATOR = %r{[:/]}

          attr_reader :partition

          attr_reader :service

          # The Region of the resource, or `nil` for a partition-global ARN.
          attr_reader :region

          # The account that owns the resource, or `nil` when the ARN omits it.
          attr_reader :account_id
          attr_reader :resource

          attr_reader :resource_segments

          # True when `value` is a string this parser can inspect at all: an
          # ASCII-compatible, validly encoded string. A non-ASCII-compatible
          # encoding makes `String#start_with?` raise, and invalid bytes make
          # `Regexp#match?` raise, so both are rejected before any comparison.
          def self.scannable?(value)
            value.is_a?(::String) && value.encoding.ascii_compatible? && value.valid_encoding?
          end

          # True when `value` announces itself as an ARN by its `arn:` prefix,
          # whether or not it is well-formed or even validly encoded. Compared
          # by bytes, since the value reaches this parser straight from the
          # caller and `String#start_with?` raises on a non-ASCII-compatible
          # encoding.
          def self.arn_like?(value)
            return false unless value.is_a?(::String)

            value.byteslice(0, PREFIX.bytesize) == PREFIX
          end

          # Parses `value` into an {Arn}, or answers `nil` when it is not a
          # well-formed ARN. Never raises, and never fills in a missing field.
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

            return nil if partition.empty? || service.empty? || resource.empty?
            return nil unless PARTITION_FORMAT.match?(partition)
            return nil unless region.empty? || REGION_FORMAT.match?(region)
            return nil unless account_id.empty? || ACCOUNT_ID_FORMAT.match?(account_id)

            new(
              partition: partition,
              service: service,
              region: region.empty? ? nil : region,
              account_id: account_id.empty? ? nil : account_id,
              resource: resource
            )
          end

          def initialize(partition:, service:, region:, account_id:, resource:)
            @partition = partition
            @service = service
            @region = region
            @account_id = account_id
            @resource = resource
            # Trailing empty segments are kept (`-1` limit), so `table/MyTable/`
            # is three segments, not two, and a caller requiring an exact count
            # rejects it as the API would.
            @resource_segments = resource.split(RESOURCE_SEPARATOR, -1)
            @bare_resource = !RESOURCE_SEPARATOR.match?(resource)
          end

          # True when the resource carries no resource type, such as an SNS
          # topic ARN.
          def bare_resource?
            @bare_resource
          end

          # The id of a typed resource: the `MyTable` of `table/MyTable`, or the
          # `my-function` of `function:my-function:PROD`. Answers `nil` unless
          # the ARN belongs to `service_name` and names one of `resource_types`.
          def typed_resource_id(service_name, resource_types)
            return nil unless service == service_name
            return nil unless resource_types.include?(resource_segments[0])

            id = resource_segments[1]
            return nil if id.nil? || id.empty?

            id
          end

          # The id of an untyped resource, such as an SNS topic name. Answers
          # `nil` unless the ARN belongs to `service_name` and its resource is
          # bare.
          def bare_resource_id(service_name)
            return nil unless service == service_name
            return nil unless bare_resource?

            resource
          end
        end
      end
    end
  end
end
