# frozen_string_literal: true

require_relative "../../../../core/telemetry/logger"
require_relative "../../../../core/utils/only_once"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Base class for all AWS service-specific tag handlers.
          class Base
            ACCOUNT_ID_FORMAT = /\A\d{12}\z/
            SUCCESS_STATUS_CODES = (200..299)
            NO_DOTTED_DNS_SUFFIXES = [].freeze
            DNS_SUFFIX_FAILURE_ONLY_ONCE = Core::Utils::OnlyOnce.new
            DNS_SUFFIX_FAILURE_DESCRIPTION =
              "Failed to read AWS partition DNS suffixes; AWS resource owner accounts will not be tagged"

            # Avoids the uninitialized instance variable warning under `-w`.
            @aws_dotted_dns_suffixes = nil

            class << self
              # DNS suffixes of every AWS partition, each with a leading dot.
              # Returns an empty list while the partition list cannot be read.
              def aws_dotted_dns_suffixes
                @aws_dotted_dns_suffixes || load_aws_dotted_dns_suffixes
              end

              private

              # Only a non-empty list is memoized, because `Aws::Partitions` is
              # autoloaded and a failed read can succeed on a later span.
              def load_aws_dotted_dns_suffixes
                suffixes = []
                if defined?(::Aws::Partitions)
                  ::Aws::Partitions.each do |partition|
                    # Older `aws-partitions` releases have no `Partition#metadata`.
                    next unless partition.respond_to?(:metadata)

                    metadata = partition.metadata
                    next unless metadata.is_a?(Hash)

                    suffixes << metadata["dnsSuffix"] << metadata["dualStackDnsSuffix"]
                  end
                end
                suffixes = suffixes.compact.uniq.map { |suffix| -".#{suffix}" }.freeze
                return @aws_dotted_dns_suffixes = suffixes unless suffixes.empty?

                DNS_SUFFIX_FAILURE_ONLY_ONCE.run do
                  reason = defined?(::Aws::Partitions) ? "reported no DNS suffix" : "is not loaded"
                  Datadog.logger.warn("#{DNS_SUFFIX_FAILURE_DESCRIPTION} (Aws::Partitions #{reason})")
                  Core::Telemetry::Logger.error(DNS_SUFFIX_FAILURE_DESCRIPTION)
                end
                NO_DOTTED_DNS_SUFFIXES
              rescue => e
                DNS_SUFFIX_FAILURE_ONLY_ONCE.run do
                  Datadog.logger.warn("#{e.class}: #{e.message}")
                  Core::Telemetry::Logger.report(e, level: :warn, description: DNS_SUFFIX_FAILURE_DESCRIPTION)
                end
                NO_DOTTED_DNS_SUFFIXES
              end
            end

            def add_tags(span, params)
            end

            # Only services whose response proves resource ownership need the request context.
            def add_owner_tags(span, params, context)
            end

            private

            def valid_account_id(value)
              value if value.is_a?(String) && ACCOUNT_ID_FORMAT.match?(value)
            end

            # A successful response from an AWS endpoint. A failed request, or a
            # 2xx from an S3 or DynamoDB compatible service such as MinIO,
            # LocalStack or DynamoDB Local, says nothing about an AWS account.
            def aws_confirmed_response?(context)
              status_code = context.safely(:status_code)
              status_code.is_a?(Integer) && SUCCESS_STATUS_CODES.cover?(status_code) &&
                aws_owned_endpoint?(context.safely(:host))
            end

            # Matched on the dot boundary so `s3.amazonaws.com.example.net` and
            # `notamazonaws.com` are not AWS.
            def aws_owned_endpoint?(host)
              return false unless host.is_a?(String)

              normalized = host.downcase.delete_suffix(".")
              Base.aws_dotted_dns_suffixes.any? { |dotted_suffix| normalized.end_with?(dotted_suffix) }
            end
          end
        end
      end
    end
  end
end
