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

            # Returned whenever the partition list cannot be read. Never
            # memoized, so a later call can still succeed.
            NO_DOTTED_DNS_SUFFIXES = [].freeze

            # A failed suffix read repeats on every subsequent span, and owner
            # tagging is optional, so the failure is surfaced once per process
            # instead of once per request. Telemetry deduplicates identical
            # logs at flush time; the `Datadog.logger` line does not, which is
            # what this gate is really for.
            DNS_SUFFIX_FAILURE_ONLY_ONCE = Core::Utils::OnlyOnce.new

            DNS_SUFFIX_FAILURE_DESCRIPTION =
              "Failed to read AWS partition DNS suffixes; AWS resource owner accounts will not be tagged"

            # Declared up front because the reader below is called before the
            # first load, and Ruby warns about reading an uninitialized
            # instance variable under `-w`. `nil` and undefined behave the same
            # for that reader, so this only removes the warning.
            @aws_dotted_dns_suffixes = nil

            class << self
              # Every AWS partition's DNS suffix, so this covers commercial,
              # GovCloud, China and the isolated partitions at once, and picks
              # up a new partition from an `aws-partitions` update instead of a
              # release here. Both the standard and the dual-stack suffix count.
              #
              # Each suffix is stored with its leading dot already attached,
              # because the only caller matches on the dot boundary. Building
              # ".#{suffix}" there instead would allocate one string per
              # partition suffix on every span.
              #
              # Fails closed: while the list cannot be read, no host is
              # recognized as AWS and no owner is ever tagged.
              def aws_dotted_dns_suffixes
                @aws_dotted_dns_suffixes || load_and_memoize_aws_dotted_dns_suffixes
              end

              private

              # Only a non-empty read is memoized. Memoizing a failure would
              # disable owner tagging for the rest of the process, and the
              # failure can be transient: `Aws::Partitions` is autoloaded, so a
              # span can run before the constant is defined. Re-reading walks
              # the in-memory partition list, with no network call and no
              # subprocess.
              def load_and_memoize_aws_dotted_dns_suffixes
                suffixes = load_aws_dotted_dns_suffixes
                return NO_DOTTED_DNS_SUFFIXES if suffixes.empty?

                @aws_dotted_dns_suffixes = suffixes
              end

              def load_aws_dotted_dns_suffixes
                unless defined?(::Aws::Partitions)
                  report_dns_suffix_failure("Aws::Partitions is not loaded")
                  return NO_DOTTED_DNS_SUFFIXES
                end

                suffixes = []
                ::Aws::Partitions.each do |partition|
                  # `Partition#metadata` was added to `aws-partitions` after
                  # the oldest release this gem still runs against, so an older
                  # one is skipped rather than raising. Skipping every partition
                  # leaves the list empty, which fails closed.
                  next unless partition.respond_to?(:metadata)

                  metadata = partition.metadata
                  next unless metadata.is_a?(Hash)

                  suffixes << metadata["dnsSuffix"] << metadata["dualStackDnsSuffix"]
                end
                # `-"..."` is `String#-@`: it returns the frozen, deduplicated
                # copy. A plain interpolated string is not frozen on every
                # supported Ruby, and this list is read by every span for the
                # rest of the process, so each entry is pinned here.
                suffixes = suffixes.compact.uniq.map { |suffix| -".#{suffix}" }.freeze

                report_dns_suffix_failure("Aws::Partitions reported no DNS suffix") if suffixes.empty?
                suffixes
              rescue => e
                report_dns_suffix_error(e)
                NO_DOTTED_DNS_SUFFIXES
              end

              def report_dns_suffix_failure(reason)
                DNS_SUFFIX_FAILURE_ONLY_ONCE.run do
                  Datadog.logger.warn("#{DNS_SUFFIX_FAILURE_DESCRIPTION} (#{reason})")
                  Core::Telemetry::Logger.error(DNS_SUFFIX_FAILURE_DESCRIPTION)
                end
              end

              def report_dns_suffix_error(error)
                DNS_SUFFIX_FAILURE_ONLY_ONCE.run do
                  Datadog.logger.warn("#{error.class}: #{error.message}")
                  Core::Telemetry::Logger.report(
                    error,
                    level: :warn,
                    description: DNS_SUFFIX_FAILURE_DESCRIPTION
                  )
                end
              end
            end

            def add_tags(span, params)
            end

            # Separate hook so handlers that only read request parameters keep
            # their arity; only services whose response proves resource
            # ownership need the request context.
            def add_owner_tags(span, params, context)
            end

            private

            def valid_account_id(value)
              value if value.is_a?(String) && ACCOUNT_ID_FORMAT.match?(value)
            end

            # Whether this response is AWS itself confirming something about an
            # AWS account. Both owner-tagging paths depend on it, because an
            # account id is only evidence of ownership once AWS has acted on it.
            #
            # The request has to have succeeded, because a rejected or failed
            # request confirms nothing.
            #
            # And the endpoint has to be AWS. S3-compatible services such as
            # MinIO, LocalStack and Ceph, and DynamoDB Local, accept the same
            # requests and resolve them against their own storage, which has no
            # AWS account behind it at all, so a 2xx from one of those is not
            # evidence about any AWS account.
            #
            # Fails closed in both directions: a status code or host that
            # cannot be read is not a success and is not AWS.
            def aws_confirmed_response?(context)
              success?(context.safely(:status_code)) && aws_owned_endpoint?(context.safely(:host))
            end

            def success?(status_code)
              status_code.is_a?(Integer) && SUCCESS_STATUS_CODES.cover?(status_code)
            end

            # Matched on the dot boundary so that a lookalike registration such
            # as `s3.amazonaws.com.example.net`, or a bare `notamazonaws.com`,
            # cannot pass as an AWS endpoint.
            #
            # What this reads is the hostname the SDK was configured to call:
            # the client's own `endpoint:`, or the one the SDK built for the
            # configured region. So the trust here is in the SDK endpoint
            # hostname, not in anything the response said about itself. If a
            # host file, a split-horizon DNS zone or a proxy sends an AWS
            # hostname somewhere else, that host still counts as AWS here.
            # What the check does rule out is the ordinary case, an
            # S3-compatible or DynamoDB-compatible service reached under its
            # own name, because LocalStack, MinIO, Ceph and DynamoDB Local are
            # configured with their own endpoint and never match.
            #
            # Reads the list off `Base` rather than `self.class`, so every
            # handler shares one list built by one loader. The suffixes already
            # carry their leading dot, so nothing is allocated per span.
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
