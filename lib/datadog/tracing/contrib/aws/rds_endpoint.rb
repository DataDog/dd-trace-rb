# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # Parses the identity Amazon RDS encodes in a DB endpoint hostname.
        #
        # Reads instance, cluster, cluster-ro, cluster-custom, Aurora Limitless, RDS Proxy,
        # Aurora Limitless DB shard group, and Aurora global writer endpoints in every AWS
        # partition. The account-specific label is matched but never returned.
        #
        # The identifier is the first label, so what it names depends on the endpoint type.
        # An instance endpoint names the DB instance. A cluster, cluster-ro, or limitless
        # endpoint names the DB cluster, not the instance it currently resolves to. A
        # cluster-custom endpoint names the custom endpoint, a proxy endpoint names the proxy
        # or the proxy endpoint, a shard group endpoint names the shard group, and a global
        # writer endpoint names the global database. A global writer endpoint follows the
        # writer across Regions, so it has no Region.
        #
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html#USER_VPC.Endpoint
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/limitless-shard.html
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-connecting.html
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-endpoints.html
        module RDSEndpoint
          TYPE_INSTANCE = "instance"
          TYPE_CLUSTER = "cluster"
          TYPE_CLUSTER_RO = "cluster-ro"
          TYPE_CLUSTER_CUSTOM = "cluster-custom"
          TYPE_LIMITLESS = "limitless"
          TYPE_PROXY = "proxy"
          TYPE_SHARD_GROUP = "shardgrp"
          TYPE_GLOBAL = "global"

          # The longest DNS name, a trailing dot on each side of a `:65535` port.
          MAX_INPUT_BYTES = 253 + 2 + 6
          MAX_CACHE_ENTRIES = 512
          RDS_LABEL_PATTERN = /\.rds\./i

          # The only partition that also puts the Region after `rds`.
          CHINA_DNS_SUFFIX = "amazonaws.com.cn"

          # Each partition's DNS suffix only serves that partition's Regions.
          #
          # @see https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-partitions/partitions.json
          REGION_PATTERNS_BY_DNS_SUFFIX = {
            # aws, and aws-us-gov
            "amazonaws.com" => /\A(?:(?:us|eu|ap|sa|ca|me|af|il|mx)-\w+-\d+|us-gov-\w+-\d+)\z/,
            # aws-cn
            CHINA_DNS_SUFFIX => /\Acn-\w+-\d+\z/,
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

          TYPES_BY_PREFIX = {
            nil => TYPE_INSTANCE,
            "cluster-" => TYPE_CLUSTER,
            "cluster-ro-" => TYPE_CLUSTER_RO,
            "cluster-custom-" => TYPE_CLUSTER_CUSTOM,
            "limitless-" => TYPE_LIMITLESS,
            "proxy-" => TYPE_PROXY,
            "endpoint.proxy-" => TYPE_PROXY,
            "shardgrp-" => TYPE_SHARD_GROUP,
          }.freeze

          # `identifier.[prefix-]hash.region.rds.<partition dns suffix>`, or in the China
          # partition also `identifier.[prefix-]hash.rds.region.amazonaws.com.cn`, where the
          # identifier follows the RDS naming rules. A global writer endpoint is
          # `identifier.global-hash.global.rds.<partition dns suffix>`. A trailing dot is
          # allowed on either side of a port, but only one without a port.
          ENDPOINT_PATTERN = /
            \A
            (?<identifier>[a-z](?:[a-z\d]|-(?!-)){0,61}[a-z\d]|[a-z])
            \.
            (?:
              global-[a-z\d]{8,16}\.global\.rds
              |
              (?<prefix>#{TYPES_BY_PREFIX.keys.compact.map { |prefix| Regexp.escape(prefix) }.join("|")})?
              [a-z\d]{8,16}
              \.
              (?:
                (?<region>[a-z]{2,4}(?:-[a-z]+){1,3}-\d{1,2})\.rds
                |
                rds\.(?<china_region>[a-z]{2,4}(?:-[a-z]+){1,3}-\d{1,2})
              )
            )
            \.
            (?<dns_suffix>#{DNS_SUFFIX_ALTERNATION})
            \.?
            (?::\d{1,5}\.?)?
            \z
          /xi

          NOT_AN_ENDPOINT = Object.new.freeze

          private_constant :MAX_INPUT_BYTES, :MAX_CACHE_ENTRIES, :RDS_LABEL_PATTERN,
            :CHINA_DNS_SUFFIX, :REGION_PATTERNS_BY_DNS_SUFFIX, :DNS_SUFFIX_ALTERNATION,
            :TYPES_BY_PREFIX, :ENDPOINT_PATTERN, :NOT_AN_ENDPOINT

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

            def parse_endpoint(hostname)
              match = ENDPOINT_PATTERN.match(hostname)
              return unless match

              dns_suffix = match[:dns_suffix].to_s.downcase
              china_region = match[:china_region]
              return if china_region && dns_suffix != CHINA_DNS_SUFFIX

              region = (match[:region] || china_region)&.downcase
              return if region && !REGION_PATTERNS_BY_DNS_SUFFIX.fetch(dns_suffix).match?(region)

              # Span tags keep these strings as they are, so they are frozen before being shared.
              {
                identifier: match[:identifier].to_s.downcase.freeze,
                endpoint_type: region ? TYPES_BY_PREFIX.fetch(match[:prefix]&.downcase) : TYPE_GLOBAL,
                region: region&.freeze,
              }
            end
          end
        end
      end
    end
  end
end
