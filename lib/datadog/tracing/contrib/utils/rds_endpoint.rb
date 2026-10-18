# frozen_string_literal: true

require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Utils
        # Reads the identity that Amazon RDS encodes in a DB endpoint hostname.
        #
        # Only what the hostname itself states is reported: no AWS API is ever called, the
        # account-specific label is matched but never emitted, and a cluster endpoint is
        # never reported as any of the instances it routes to.
        #
        # ## Tag contract
        #
        # Three namespaces, each chosen for where the tag has to join:
        #
        # * `aws.rds.identifier` and `aws.rds.endpoint_type` are this library's own tags.
        #   `aws.rds.identifier` is the leftmost hostname label, and what it identifies
        #   depends on `aws.rds.endpoint_type`: a DB instance for `instance`, a DB cluster
        #   for `cluster` and `cluster-ro`, a custom endpoint for `cluster-custom`, and an
        #   RDS Proxy for `proxy`. The two tags are only meaningful read together.
        # * `aws.region` is the tag the AWS SDK integration already emits, so one query
        #   covers both DB spans and SDK spans.
        # * `dbinstanceidentifier` and `dbclusteridentifier` carry no prefix on purpose:
        #   they are the join keys of the Amazon RDS integration's own metrics, and a
        #   prefixed copy would not join. Each is emitted only when the hostname names
        #   that kind of resource outright, so an instance endpoint never sets
        #   `dbclusteridentifier`, a cluster or reader endpoint never sets
        #   `dbinstanceidentifier`, and a `cluster-custom` or `proxy` endpoint names
        #   neither resource and so sets neither tag.
        #
        #   Both names, and the rule that the `cluster-` prefix is what selects between
        #   them, are what Datadog's own components already do: `integrations-core`
        #   derives exactly these two tags from an RDS endpoint hostname in
        #   `rds_parse_tags_from_endpoint`, the Agent's Aurora autodiscovery listener
        #   publishes `dbclusteridentifier` as a template variable, and the Database
        #   Monitoring documentation tags discovered clusters with it.
        #
        #   This parser is stricter than `rds_parse_tags_from_endpoint` in two ways, both
        #   deliberate: it reads every AWS partition rather than `rds.amazonaws.com`
        #   alone, and it does not report a `cluster-custom` endpoint as naming a cluster,
        #   because a custom endpoint names a user-defined member list rather than the
        #   cluster itself.
        #
        # ## Endpoint forms
        #
        # Read: instance, cluster, cluster-ro (reader), cluster-custom, and RDS Proxy
        # default endpoints, in every AWS partition.
        #
        # Deliberately not read, each leaving the span with no RDS tags at all, because
        # no authoritative current grammar pins the hostname shape well enough to tag it
        # without guessing: Aurora global cluster endpoints, RDS Proxy *custom* endpoints
        # (`name.endpoint.proxy-<label>.<region>...`), and Aurora Limitless DB shard group
        # endpoints (`name.shardgrp-<label>.<region>...`). Any other unrecognized label
        # prefix is treated the same way. Adding no tag is always correct; adding a wrong
        # one is not, so an unrecognized form fails the whole match rather than falling
        # back to a guess.
        #
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html#USER_VPC.Endpoint
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html
        # @see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-endpoints.html
        # @see https://github.com/DataDog/integrations-core/blob/master/datadog_checks_base/datadog_checks/base/utils/aws.py
        # @see https://github.com/DataDog/datadog-agent/blob/main/comp/core/autodiscovery/listeners/dbm_aurora.go
        # @see https://docs.datadoghq.com/database_monitoring/guide/aurora_autodiscovery/
        module RDSEndpoint
          # 253 bytes for the longest DNS name, 1 more for the root label's trailing dot,
          # and 6 for a `:65535` port suffix.
          #
          # The limit is applied to the value exactly as given, before any trimming,
          # because trimming allocates and nothing here may allocate before a hostname is
          # known to be worth parsing. A value padded with more than that much surrounding
          # whitespace is therefore rejected rather than trimmed first.
          MAX_INPUT_BYTES = 253 + 1 + 6

          # Distinct endpoints one process talks to, well past any realistic count, so
          # this is a memory ceiling against a pathological caller rather than a working
          # set anyone is expected to reach.
          MAX_CACHE_ENTRIES = 512

          # A port is only removed, never reported, so its numeric range has no bearing on
          # the identity; bounding its length to the widest a port can be is all that is
          # needed to bound the scan.
          PORT_PATTERN = /\A\d{1,5}\z/

          # Every RDS endpoint carries the `.rds.` label immediately before its partition's
          # DNS suffix, so a hostname without it cannot be one.
          #
          # This is the gate that keeps the common case -- a database that is not on RDS --
          # off the parsing path, so it must not allocate. `Regexp#match?` is what makes
          # that free: it reports only whether the pattern matched, so unlike `=~` or
          # `#match` it builds no `MatchData` and does not set `$~`.
          RDS_LABEL_PATTERN = /\.rds\./i

          # The suffix an RDS endpoint carries after its account label, per AWS partition:
          # `rds.` followed by that partition's DNS suffix.
          #
          # A partition's DNS suffix serves only that partition's Regions, so the Region
          # and the suffix have to agree, and a hostname where they disagree is not an RDS
          # endpoint. Each value below is that partition's own Region pattern, transcribed
          # from the `regionRegex` published alongside the suffix. `amazonaws.com` is the
          # one suffix serving two partitions -- commercial and GovCloud -- so it accepts
          # either of their Region shapes and no others.
          #
          # `\w` is kept as published even though a Region never contains `_`: the Region
          # reaching this check has already been narrowed to letters, hyphens, and digits
          # by {ENDPOINT_PATTERN}, so the transcription stays faithful to its source
          # without widening what is accepted.
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

          # Built from the table above so the two can never drift apart. Longest first, so
          # `amazonaws.com.cn` is never read as `amazonaws.com` with a stray `.cn` left
          # over.
          DNS_SUFFIX_ALTERNATION = REGION_PATTERNS_BY_DNS_SUFFIX
            .keys
            .sort_by { |suffix| -suffix.length }
            .map { |suffix| Regexp.escape(suffix) }
            .join("|")

          # `identifier.[prefix-]accountlabel.region.rds.<partition dns suffix>`, where the
          # identifier obeys the RDS naming rules: a leading letter, no doubled hyphen, no
          # trailing hyphen, and at most 63 characters.
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

          ENDPOINT_TYPES_BY_PREFIX = {
            nil => Contrib::Ext::RDS::ENDPOINT_TYPE_INSTANCE,
            "cluster-" => Contrib::Ext::RDS::ENDPOINT_TYPE_CLUSTER,
            "cluster-ro-" => Contrib::Ext::RDS::ENDPOINT_TYPE_CLUSTER_RO,
            "cluster-custom-" => Contrib::Ext::RDS::ENDPOINT_TYPE_CLUSTER_CUSTOM,
            "proxy-" => Contrib::Ext::RDS::ENDPOINT_TYPE_PROXY,
          }.freeze

          # Tells a cached "this is not an endpoint" apart from "not cached".
          NOT_AN_ENDPOINT = Object.new.freeze

          private_constant :MAX_INPUT_BYTES, :MAX_CACHE_ENTRIES, :PORT_PATTERN,
            :RDS_LABEL_PATTERN, :REGION_PATTERNS_BY_DNS_SUFFIX, :DNS_SUFFIX_ALTERNATION,
            :ENDPOINT_PATTERN, :ENDPOINT_TYPES_BY_PREFIX, :NOT_AN_ENDPOINT

          # Guarded by `@cache_mutex`, never read or written outside it.
          #
          # Keyed by the hostname exactly as given, not by a normalized one, because
          # normalizing first would allocate the very string the cache exists to avoid.
          # The cost is capacity rather than correctness: `host`, `HOST`, and `host:5432`
          # are three entries naming one endpoint, so a caller that varies the surface
          # form of its hostname fits fewer distinct endpoints in the same
          # {MAX_CACHE_ENTRIES} slots. Connection configuration is written once and reused
          # verbatim, so in practice one endpoint is one entry.
          #
          # `Core::Utils::LRUCache` is deliberately not used: it records recency by
          # re-inserting the key it was handed, and `Hash#[]=` stores a frozen copy of an
          # unfrozen `String` key, so every cache *hit* would allocate a string. Reads
          # here only read.
          #
          # One uncontended `Mutex` still costs far less than what re-parsing allocates (a
          # `MatchData` plus a string per captured field), and it is the only arrangement
          # that is correct on MRI, JRuby, and TruffleRuby alike: the latter two run Ruby
          # threads in parallel, where an unguarded `Hash` can be read while it is being
          # rehashed.
          @cache = {}
          @cache_mutex = Mutex.new

          class << self
            # Identity stated by `hostname`, or `nil` when it does not state one.
            #
            # The returned hash is frozen and shared between callers.
            def parse(hostname)
              return unless hostname.is_a?(String)
              return if hostname.bytesize > MAX_INPUT_BYTES
              # An RDS endpoint is ASCII throughout, so this rejects nothing real. It also
              # rejects invalid byte sequences, on which matching a pattern would raise.
              return unless hostname.ascii_only?
              return unless RDS_LABEL_PATTERN.match?(hostname)

              fetch_or_parse(hostname)
            end

            # Adds the RDS tags `hostname` states to `span`, and nothing at all when it
            # states none, so a span for a database that is not on RDS is untouched.
            def annotate!(span, hostname)
              endpoint = parse(hostname)
              return unless endpoint

              identifier = endpoint[:identifier]
              endpoint_type = endpoint[:endpoint_type]

              span.set_tag(Contrib::Ext::RDS::TAG_IDENTIFIER, identifier)
              span.set_tag(Contrib::Ext::RDS::TAG_ENDPOINT_TYPE, endpoint_type)
              span.set_tag(Contrib::Ext::RDS::TAG_REGION, endpoint[:region])

              # Join keys of RDS's own metrics, so each is emitted only when the hostname
              # names that kind of resource outright.
              case endpoint_type
              when Contrib::Ext::RDS::ENDPOINT_TYPE_INSTANCE
                span.set_tag(Contrib::Ext::RDS::TAG_DB_INSTANCE_IDENTIFIER, identifier)
              when Contrib::Ext::RDS::ENDPOINT_TYPE_CLUSTER, Contrib::Ext::RDS::ENDPOINT_TYPE_CLUSTER_RO
                span.set_tag(Contrib::Ext::RDS::TAG_DB_CLUSTER_IDENTIFIER, identifier)
              end
            end

            private

            def fetch_or_parse(hostname)
              @cache_mutex.synchronize do
                cached = @cache[hostname]

                if cached.nil?
                  endpoint = parse_endpoint(hostname)
                  # Shared between callers from here on, so it must not be mutable.
                  cached = endpoint ? endpoint.freeze : NOT_AN_ENDPOINT
                  # Full: evict the oldest insertion rather than every entry, so a process
                  # that talks to more endpoints than the cache holds gives up one
                  # memoized endpoint per new one instead of all of them at once. Ruby
                  # hashes iterate in insertion order, so `shift` removes the oldest
                  # insertion. Insertion order, not use order: tracking recency is what
                  # would make a cache hit allocate.
                  @cache.shift if @cache.size >= MAX_CACHE_ENTRIES
                  # `Hash#[]=` stores a frozen copy of an unfrozen String key, so a caller
                  # mutating the string it passed cannot corrupt this.
                  @cache[hostname] = cached
                end

                cached unless cached.equal?(NOT_AN_ENDPOINT)
              end
            end

            # Normalization runs in a fixed and observable order: surrounding whitespace,
            # then a `:port` suffix, then the root label's trailing dot. So
            # `...rds.amazonaws.com.:5432` parses, because the root dot terminates the
            # hostname and the port follows it, while `...rds.amazonaws.com:5432.` does
            # not, because a trailing dot is not part of a port. Both are pinned by spec.
            def parse_endpoint(hostname)
              candidate = strip_port(hostname.strip)
              return unless candidate

              match = ENDPOINT_PATTERN.match(candidate.chomp("."))
              return unless match

              region = match[:region].downcase
              return unless REGION_PATTERNS_BY_DNS_SUFFIX.fetch(match[:dns_suffix].downcase).match?(region)

              {
                identifier: match[:identifier].downcase,
                endpoint_type: ENDPOINT_TYPES_BY_PREFIX.fetch(match[:prefix]&.downcase),
                region: region,
              }
            end

            # `String#[]` is typed as returning `String?`, so both slices are coerced
            # before use; neither can actually be `nil` at these offsets.
            def strip_port(candidate)
              separator = candidate.rindex(":")
              return candidate unless separator
              return unless PORT_PATTERN.match?(candidate[(separator + 1)..-1].to_s)

              host = candidate[0, separator].to_s
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
