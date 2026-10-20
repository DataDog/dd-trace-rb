# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # A strict, non-throwing parser for Amazon Resource Names.
        #
        # SDK request parameters often carry a full ARN where this integration
        # historically assumed a bare name (DynamoDB's `TableName`, and the
        # stream, topic, function and state-machine ARNs of the other
        # services). {.parse} validates the whole structure and answers `nil`
        # for anything malformed, so callers fall back to the raw parameter
        # instead of rescuing on a hot path or indexing into `String#split`
        # output that cannot tell the forms apart.
        #
        # A field the ARN omits stays `nil` rather than guessed: mis-attributing
        # a span to the wrong account is worse than to none. The Region a
        # parsed ARN carries is the *target* resource's, not necessarily the
        # request endpoint's, and is never written to a tag of its own, so
        # `aws.region` keeps its established meaning; each emitted ARN tag
        # carries the target Region itself.
        #
        # @see https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html
        class Arn
          PREFIX = "arn:"

          # `arn:<partition>:<service>:<region>:<account-id>:<resource>`
          SEGMENT_COUNT = 6

          # `aws`, plus the `aws-cn`, `aws-us-gov` and ISO partitions.
          PARTITION_FORMAT = /\Aaws(?:-[a-z0-9]+)*\z/

          # Region codes are lowercase, hyphen-separated and end in a digit
          # (`us-east-1`, `cn-north-1`, `us-gov-west-1`, `us-iso-east-1`).
          REGION_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*-\d+\z/

          ACCOUNT_ID_FORMAT = /\A\d{12}\z/

          # A resource is either a bare id, or a type and id joined by `/` or
          # `:`. Both delimiters are used interchangeably across services, and
          # none of the resource names handled here may contain either, so they
          # are equivalent for identity extraction.
          RESOURCE_SEPARATOR = %r{[:/]}

          attr_reader :partition

          attr_reader :service

          # The Region of the resource, or `nil` for a partition-global ARN.
          attr_reader :region

          # The account that owns the resource, or `nil` when the ARN omits it.
          attr_reader :account_id

          attr_reader :resource

          attr_reader :resource_segments

          # True when `value` is a string this parser can inspect at all.
          #
          # A non-ASCII-compatible encoding cannot be an ARN, and both that
          # case and invalid bytes must be rejected before any comparison:
          # `String#start_with?` raises `Encoding::CompatibilityError` for the
          # former and `Regexp#match?` raises `ArgumentError` for the latter.
          # Request parameters reach this parser straight from the caller, so
          # either is reachable with ordinary input. Callers running their own
          # patterns over a parameter share this guard.
          def self.scannable?(value)
            value.is_a?(::String) && value.encoding.ascii_compatible? && value.valid_encoding?
          end

          # Parses `value` into an {Arn}, or answers `nil` when it is not a
          # well-formed ARN. Never raises, and never fills in a missing field.
          def self.parse(value)
            return nil unless scannable?(value)
            return nil unless value.start_with?(PREFIX)

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
            # Trailing empty segments are kept, so a caller that requires a
            # resource of exactly N segments reads `table/MyTable/` as three
            # segments rather than two and rejects it, as the API would.
            @resource_segments = resource.split(RESOURCE_SEPARATOR, -1)
            @bare_resource = !RESOURCE_SEPARATOR.match?(resource)
          end

          # True when the resource is a bare id carrying no resource type, which
          # is the shape of an SNS topic ARN.
          def bare_resource?
            @bare_resource
          end

          # The id of a typed resource: the `MyTable` of `table/MyTable`, or the
          # `my-function` of `function:my-function:PROD`.
          #
          # Answers `nil` unless the ARN belongs to `service_name` and names one
          # of `resource_types`, so an unrelated ARN -- an SNS mobile platform
          # endpoint, a Lambda layer, another service's resource passed by
          # mistake -- is never mistaken for the resource the caller wanted.
          def typed_resource_id(service_name, resource_types)
            return nil unless service == service_name
            return nil unless resource_types.include?(resource_segments[0])

            id = resource_segments[1]
            return nil if id.nil? || id.empty?

            id
          end

          # The id of an untyped resource, such as an SNS topic name. Answers
          # `nil` unless the ARN belongs to `service_name` and its resource is
          # bare, which is what distinguishes a topic ARN from the endpoint,
          # platform application and subscription ARNs of the same service.
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
