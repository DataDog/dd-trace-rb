# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # Parses the identity Amazon RDS encodes in a DB endpoint hostname.
        #
        # Reads instance, cluster, cluster-ro, cluster-custom, and RDS Proxy default
        # endpoints in every AWS partition. Any other form, including Aurora global,
        # RDS Proxy custom, and Aurora Limitless shard group endpoints, is not parsed.
        # The account-specific label is matched but never returned.
        #
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html#USER_VPC.Endpoint
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-endpoints.html
        module RDSEndpoint
          TYPE_INSTANCE = "instance"
          TYPE_CLUSTER = "cluster"
          TYPE_CLUSTER_RO = "cluster-ro"
          TYPE_CLUSTER_CUSTOM = "cluster-custom"
          TYPE_PROXY = "proxy"

          # The longest DNS name, its root label's trailing dot, and a `:65535` port.
          MAX_INPUT_BYTES = 253 + 1 + 6
          MAX_CACHE_ENTRIES = 512
          PORT_PATTERN = /\A\d{1,5}\z/
          RDS_LABEL_PATTERN = /\.rds\./i

          # Each partition's DNS suffix only serves that partition's Regions.
          #
          # @see https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-partitions/partitions.json
          REGION_PATTERNS_BY_DNS_SUFFIX = {
            # aws, and aws-us-gov
            "amazonaws.com" => /\A(?:(?:us|eu|ap|sa|ca|me|af|il|mx)-\w+-\d+|us-gov-\w+-\d+)\z/,
            # aws-cn
            "amazonaws.com.cn" => /\Acn-\w+-\d+\z/,
            # aws-eusc
            "amazonaws.eu" => /\Aeusc-(?:de)-\w+-\d+\z/,
            # aws-iso
            "c2s.ic.gov" => /\Aus-iso-\w+-\d+\z/,
            # aws-iso-b
            "sc2s.sgov.gov" => /\Aus-isob-\w+-\d+\z/,
            # aws-iso-e
            "cloud.adc-e.uk" => /\Aeu-isoe-\w+-\d+\z/,
            # aws-iso-f
            "csp.hci.ic.gov" => /\Aus-isof-\w+-\d+\z/,
          }.freeze

          # Longest first, so `amazonaws.com.cn` is never read as `amazonaws.com`.
          DNS_SUFFIX_ALTERNATION = REGION_PATTERNS_BY_DNS_SUFFIX
            .keys
            .sort_by { |suffix| -suffix.length }
            .map { |suffix| Regexp.escape(suffix) }
            .join("|")

          # `identifier.[prefix-]accountlabel.region.rds.<partition dns suffix>`, where the
          # identifier follows the RDS naming rules.
          ENDPOINT_PATTERN = /
            \A
            (?<identifier>[a-z](?:[a-z\d]|-(?!-)){0,61}[a-z\d]|[a-z])
            \.
            (?<prefix>cluster-ro-|cluster-custom-|cluster-|proxy-)?
            [a-z\d]{1,63}
            \.
            (?<region>[a-z]{2,4}(?:-[a-z]+){1,3}-\d{1,2})
            \.rds\.
            (?<dns_suffix>#{DNS_SUFFIX_ALTERNATION})
            \z
          /xi

          TYPES_BY_PREFIX = {
            nil => TYPE_INSTANCE,
            "cluster-" => TYPE_CLUSTER,
            "cluster-ro-" => TYPE_CLUSTER_RO,
            "cluster-custom-" => TYPE_CLUSTER_CUSTOM,
            "proxy-" => TYPE_PROXY,
          }.freeze

          NOT_AN_ENDPOINT = Object.new.freeze

          private_constant :MAX_INPUT_BYTES, :MAX_CACHE_ENTRIES, :PORT_PATTERN,
            :RDS_LABEL_PATTERN, :REGION_PATTERNS_BY_DNS_SUFFIX, :DNS_SUFFIX_ALTERNATION,
            :ENDPOINT_PATTERN, :TYPES_BY_PREFIX, :NOT_AN_ENDPOINT

          # Keyed by the hostname as given, so a cache hit allocates nothing.
          # `Core::Utils::LRUCache` is not used because it re-inserts the key on every hit.
          @cache = {}
          @cache_mutex = Mutex.new

          class << self
            # Returns a frozen `{identifier:, endpoint_type:, region:}` hash shared between
            # callers, or `nil` when `hostname` is not an RDS endpoint.
            def parse(hostname)
              return unless hostname.is_a?(String)
              return if hostname.bytesize > MAX_INPUT_BYTES
              return unless hostname.ascii_only?
              return unless RDS_LABEL_PATTERN.match?(hostname)

              fetch_or_parse(hostname)
            end

            private

            def fetch_or_parse(hostname)
              @cache_mutex.synchronize do
                cached = @cache[hostname]

                if cached.nil?
                  cached = parse_endpoint(hostname)&.freeze || NOT_AN_ENDPOINT
                  # Evicts the oldest insertion, since hashes keep insertion order.
                  @cache.shift if @cache.size >= MAX_CACHE_ENTRIES
                  @cache[hostname] = cached
                end

                cached unless cached.equal?(NOT_AN_ENDPOINT)
              end
            end

            # Removes surrounding whitespace, then a `:port` suffix, then the root label's
            # trailing dot, in that order.
            def parse_endpoint(hostname)
              host = strip_port(hostname.strip)
              return unless host

              match = ENDPOINT_PATTERN.match(host.chomp("."))
              return unless match

              region = match[:region].downcase
              return unless REGION_PATTERNS_BY_DNS_SUFFIX.fetch(match[:dns_suffix].downcase).match?(region)

              {
                identifier: match[:identifier].downcase,
                endpoint_type: TYPES_BY_PREFIX.fetch(match[:prefix]&.downcase),
                region: region,
              }
            end

            def strip_port(hostname)
              host, separator, port = hostname.rpartition(":")
              return hostname if separator.empty?
              return unless PORT_PATTERN.match?(port)
              # A remaining colon means an IPv6 literal, which is never an RDS endpoint.
              return if host.include?(":")

              host
            end
          end
        end
      end
    end
  end
end
