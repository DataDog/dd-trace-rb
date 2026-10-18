require "spec_helper"

require "datadog/tracing/contrib/utils/rds_endpoint"
require "datadog/tracing/span_operation"

RSpec.describe Datadog::Tracing::Contrib::Utils::RDSEndpoint do
  let(:ext) { Datadog::Tracing::Contrib::Ext::RDS }

  # The parser's cache is process-wide by design. Examples that assert on it, or that
  # count allocations, start from a known state.
  def clear_cache!
    described_class.instance_variable_get(:@cache).clear
  end

  def cache_size
    described_class.instance_variable_get(:@cache).size
  end

  # Measures twice and reports the second run, so that whatever the measurement itself
  # touches for the first time -- inline caches, the parser's own cache entry, the
  # hostname's cached code range -- is not counted against the code under test.
  def allocations_for(iterations, &block)
    measure_allocations(iterations, &block)
    measure_allocations(iterations, &block)
  end

  def measure_allocations(iterations)
    GC.start
    GC.disable
    before = GC.stat(:total_allocated_objects)
    iterations.times { yield }
    GC.stat(:total_allocated_objects) - before
  ensure
    GC.enable
  end

  describe ".parse" do
    subject(:parse) { described_class.parse(hostname) }

    # One endpoint per AWS partition, each under the DNS suffix that partition actually
    # serves. The suffixes and the Region shapes come from the `aws-partitions` data:
    # `rds.` plus the partition's `dnsSuffix`, with a Region matching its `regionRegex`.
    context "with an endpoint in each AWS partition" do
      {
        # aws
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" => "us-east-1",
        "orders-db.cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" => "eu-west-1",
        "orders-db.cdbfa1b2c3d4.mx-central-1.rds.amazonaws.com" => "mx-central-1",
        "orders-db.cdbfa1b2c3d4.il-central-1.rds.amazonaws.com" => "il-central-1",
        # aws-us-gov, which shares the commercial DNS suffix
        "gov-db.cdbfa1b2c3d4.us-gov-west-1.rds.amazonaws.com" => "us-gov-west-1",
        "gov-db.cdbfa1b2c3d4.us-gov-east-1.rds.amazonaws.com" => "us-gov-east-1",
        # aws-cn
        "cn-db.cdbfa1b2c3d4.cn-north-1.rds.amazonaws.com.cn" => "cn-north-1",
        "cn-db.cdbfa1b2c3d4.cn-northwest-1.rds.amazonaws.com.cn" => "cn-northwest-1",
        # aws-iso
        "iso-db.cdbfa1b2c3d4.us-iso-east-1.rds.c2s.ic.gov" => "us-iso-east-1",
        # aws-iso-b
        "isob-db.cdbfa1b2c3d4.us-isob-east-1.rds.sc2s.sgov.gov" => "us-isob-east-1",
        # aws-iso-e
        "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk" => "eu-isoe-west-1",
        # aws-iso-f
        "isof-db.cdbfa1b2c3d4.us-isof-south-1.rds.csp.hci.ic.gov" => "us-isof-south-1",
        # aws-eusc
        "eusc-db.cdbfa1b2c3d4.eusc-de-east-1.rds.amazonaws.eu" => "eusc-de-east-1",
      }.each do |host, region|
        context "with #{host}" do
          let(:hostname) { host }

          it { is_expected.to include(region: region, endpoint_type: "instance", identifier: host.split(".").first) }
        end
      end
    end

    context "with each endpoint type" do
      {
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" =>
          {identifier: "orders-db", endpoint_type: "instance", region: "us-east-1"},
        "orders.cluster-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" =>
          {identifier: "orders", endpoint_type: "cluster", region: "us-east-1"},
        "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" =>
          {identifier: "orders", endpoint_type: "cluster-ro", region: "eu-west-1"},
        "analytics.cluster-custom-cdbfa1b2c3d4.ap-southeast-2.rds.amazonaws.com" =>
          {identifier: "analytics", endpoint_type: "cluster-custom", region: "ap-southeast-2"},
        "orders-proxy.proxy-cdbfa1b2c3d4.us-east-2.rds.amazonaws.com" =>
          {identifier: "orders-proxy", endpoint_type: "proxy", region: "us-east-2"},
      }.each do |host, expected|
        context "with #{host}" do
          let(:hostname) { host }

          it { is_expected.to eq(expected) }
        end
      end

      context "with a cluster endpoint outside the commercial partition" do
        let(:hostname) { "orders.cluster-cdbfa1b2c3d4.us-iso-east-1.rds.c2s.ic.gov" }

        it { is_expected.to eq(identifier: "orders", endpoint_type: "cluster", region: "us-iso-east-1") }
      end
    end

    # A partition's DNS suffix serves only that partition's Regions. A hostname where the
    # two disagree does not exist, so it is not an RDS endpoint and must not be tagged as
    # one -- in particular, an ISO-style Region is never served under `amazonaws.com`.
    context "with a Region that does not belong to the partition of its DNS suffix" do
      [
        "iso-db.cdbfa1b2c3d4.us-iso-east-1.rds.amazonaws.com",
        "isob-db.cdbfa1b2c3d4.us-isob-east-1.rds.amazonaws.com",
        "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.amazonaws.com",
        "isof-db.cdbfa1b2c3d4.us-isof-south-1.rds.amazonaws.com",
        "eusc-db.cdbfa1b2c3d4.eusc-de-east-1.rds.amazonaws.com",
        "cn-db.cdbfa1b2c3d4.cn-north-1.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.cn",
        "gov-db.cdbfa1b2c3d4.us-gov-west-1.rds.amazonaws.com.cn",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.c2s.ic.gov",
        "iso-db.cdbfa1b2c3d4.us-iso-east-1.rds.sc2s.sgov.gov",
        "isob-db.cdbfa1b2c3d4.us-isob-east-1.rds.c2s.ic.gov",
        "isoe-db.cdbfa1b2c3d4.us-iso-east-1.rds.cloud.adc-e.uk",
        "isof-db.cdbfa1b2c3d4.us-isob-east-1.rds.csp.hci.ic.gov",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.eu",
        # aws-eusc only serves `eusc-de-*`
        "eusc-db.cdbfa1b2c3d4.eusc-fr-east-1.rds.amazonaws.eu",
        # the commercial partition has no such Region prefix
        "orders-db.cdbfa1b2c3d4.xx-east-1.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.cn-north-1.rds.amazonaws.eu",
      ].each do |host|
        context "with #{host}" do
          let(:hostname) { host }

          it { is_expected.to be_nil }
        end
      end
    end

    # Each of these is a real endpoint form whose current grammar is not pinned well
    # enough to tag without guessing, so the parser reports no identity at all rather
    # than a wrong one. Pinned here so that adding support is a deliberate change.
    context "with an endpoint form that is deliberately not read" do
      {
        "Aurora global cluster" => "global-orders.global-cdbfa1b2c3d4.global.rds.amazonaws.com",
        "RDS Proxy custom endpoint" => "readonly.endpoint.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "Aurora Limitless DB shard group" => "orders.shardgrp-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
      }.each do |description, host|
        context "with a #{description} endpoint" do
          let(:hostname) { host }

          it { is_expected.to be_nil }
        end
      end
    end

    context "with trailing dots, ports, case, and whitespace" do
      {
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com." => "trailing dot",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:3306" => "port",
        "ORDERS-DB.CDBFA1B2C3D4.US-EAST-1.RDS.AMAZONAWS.COM" => "upper case",
        "Orders-Db.Cdbfa1b2c3d4.Us-East-1.Rds.Amazonaws.Com" => "mixed case",
        "  orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com\n" => "surrounding whitespace",
        "\torders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.:5432 " => "all of them at once",
      }.each do |host, description|
        context "with #{description}" do
          let(:hostname) { host }

          it "normalizes to the same identity" do
            expect(parse).to eq(identifier: "orders-db", endpoint_type: "instance", region: "us-east-1")
          end
        end
      end

      context "with an upper-case ISOE endpoint" do
        let(:hostname) { "ISOE-DB.CDBFA1B2C3D4.EU-ISOE-WEST-1.RDS.CLOUD.ADC-E.UK" }

        it { is_expected.to eq(identifier: "isoe-db", endpoint_type: "instance", region: "eu-isoe-west-1") }
      end

      context "with a China endpoint carrying a trailing dot and a port" do
        let(:hostname) { "cn-db.cdbfa1b2c3d4.cn-north-1.rds.amazonaws.com.cn.:3306" }

        it { is_expected.to eq(identifier: "cn-db", endpoint_type: "instance", region: "cn-north-1") }
      end

      # Normalization order is whitespace, then port, then the root label's trailing dot,
      # and that order is observable: the root dot terminates the hostname, so a port may
      # follow it, but a dot is never part of a port. Both directions are pinned so the
      # asymmetry cannot change unnoticed.
      context "with a trailing dot before the port" do
        let(:hostname) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.:5432" }

        it { is_expected.to include(identifier: "orders-db") }
      end

      context "with a trailing dot after the port" do
        let(:hostname) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:5432." }

        it { is_expected.to be_nil }
      end
    end

    context "with identifiers at the edges of the RDS naming rules" do
      context "with a single-character identifier" do
        let(:hostname) { "a.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to include(identifier: "a") }
      end

      context "with a 63-character identifier" do
        let(:identifier) { "a" + ("b" * 62) }
        let(:hostname) { "#{identifier}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to include(identifier: identifier) }
      end

      context "with a 64-character identifier" do
        let(:hostname) { "#{"a" + ("b" * 63)}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to be_nil }
      end

      context "with digits and single hyphens" do
        let(:hostname) { "db-1-shard-7.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to include(identifier: "db-1-shard-7") }
      end
    end

    context "with adversarial hostnames" do
      [
        # an RDS endpoint as a prefix of a hostname the caller controls
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.attacker.example",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.attacker.com",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.evil.rds.amazonaws.com.co",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.c2s.ic.gov.attacker.example",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.cloud.adc-e.uk.attacker.example",
        # a DNS suffix that merely looks like a partition's
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.co",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com.cn.cn",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.eu.cn",
        "orders-db.cdbfa1b2c3d4.us-iso-east-1.rds.c2s.ic.gov.uk",
        "orders-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.co.uk",
        "orders-db.cdbfa1b2c3d4.us-isob-east-1.rds.sc2s.sgov.gov.cn",
        "orders-db.cdbfa1b2c3d4.us-isof-south-1.rds.csp.hci.ic.gov.uk",
        # the `.rds.` label alone proves nothing
        "rds.amazonaws.com",
        "not-really.rds.example.com",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.internal",
        # a different AWS service under the same suffix
        "orders-db.cdbfa1b2c3d4.us-east-1.docdb.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.us-east-1.redshift.amazonaws.com",
        # an unrecognized account-label prefix
        "orders-db.writer-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "orders.cluster-cdbfa1-b2c3d4.us-east-1.rds.amazonaws.com",
        # the wrong number of labels
        "extra.orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "orders-db.us-east-1.rds.amazonaws.com",
        "orders-db..us-east-1.rds.amazonaws.com",
        ".cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        # identifiers the RDS naming rules forbid
        "1db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "db-.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "db--shard.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "orders_db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        # Region shapes that are not Regions
        "orders-db.cdbfa1b2c3d4.useast1.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.us-east.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.us-east-999.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.u-east-1.rds.amazonaws.com",
        "orders-db.cdbfa1b2c3d4.us_east_1.rds.amazonaws.com",
        # ports that are not ports
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:3306:3306",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:notaport",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:123456",
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com..",
        # not hostnames at all
        "127.0.0.1",
        "localhost",
        "[2600:1f14::1]:5432",
        "::1",
        "/var/run/postgresql/.s.PGSQL.5432",
        "http://orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "user:password@orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "",
        "   ",
      ].each do |host|
        context "with #{host.inspect}" do
          let(:hostname) { host }

          it { is_expected.to be_nil }
        end
      end

      context "with a non-ASCII homoglyph in the identifier" do
        let(:hostname) { "ordérs-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to be_nil }
      end

      context "with invalid byte sequences" do
        let(:hostname) { (+"orders\xFF-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com").force_encoding(Encoding::UTF_8) }

        it "returns nil without raising" do
          expect { parse }.not_to raise_error
          expect(parse).to be_nil
        end
      end

      context "with a hostname longer than a DNS name" do
        let(:hostname) { "#{"a" * 300}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to be_nil }
      end

      context "with a long run of hyphens" do
        let(:hostname) { "a#{"-" * 200}b.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it { is_expected.to be_nil }
      end

      context "with many repetitions of the gate's label" do
        let(:hostname) { ".rds." * 50 }

        it { is_expected.to be_nil }
      end

      [nil, 3306, :host, ["orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com"], Object.new].each do |value|
        context "with the non-string #{value.class}" do
          let(:hostname) { value }

          it { is_expected.to be_nil }
        end
      end
    end

    context "with a result that callers share" do
      let(:hostname) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "is frozen, so one caller cannot change what another reads" do
        expect(parse).to be_frozen
      end

      it "is the same object every time, so a repeated endpoint is parsed once" do
        expect(described_class.parse(hostname)).to be(described_class.parse(hostname))
      end
    end
  end

  describe "the endpoint cache" do
    before { clear_cache! }

    after { clear_cache! }

    def cached?(hostname)
      described_class.instance_variable_get(:@cache).key?(hostname)
    end

    def host_for(i)
      "db#{i}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com"
    end

    it "fills to its limit and no further" do
      512.times { |i| described_class.parse(host_for(i)) }

      expect(cache_size).to eq(512)
    end

    it "stays bounded when fed far more distinct endpoints than it holds" do
      600.times { |i| described_class.parse(host_for(i)) }

      expect(cache_size).to eq(512)
    end

    # Overflow drops one entry per new endpoint rather than the whole cache, so a process
    # that sees more endpoints than the cache holds keeps its recent ones memoized.
    it "evicts one oldest insertion per new endpoint once full" do
      512.times { |i| described_class.parse(host_for(i)) }

      described_class.parse(host_for(512))

      expect(cache_size).to eq(512)
      expect(cached?(host_for(0))).to be(false)
      expect(cached?(host_for(1))).to be(true)
      expect(cached?(host_for(512))).to be(true)
    end

    it "keeps the most recently inserted entries after a long overflow" do
      700.times { |i| described_class.parse(host_for(i)) }

      expect(cache_size).to eq(512)
      # 700 insertions minus 512 slots leaves the oldest 188 evicted and the rest held.
      expect(cached?(host_for(187))).to be(false)
      expect(cached?(host_for(188))).to be(true)
      expect(cached?(host_for(699))).to be(true)
    end

    it "still answers correctly for an endpoint it has evicted" do
      600.times { |i| described_class.parse(host_for(i)) }

      expect(cached?(host_for(0))).to be(false)
      expect(described_class.parse(host_for(0))).to eq(
        identifier: "db0", endpoint_type: "instance", region: "us-east-1"
      )
    end

    it "remembers hostnames that are not endpoints, so a bad host is parsed once" do
      expect(described_class.parse("not-really.rds.example.com")).to be_nil
      expect(described_class.parse("not-really.rds.example.com")).to be_nil

      expect(cache_size).to eq(1)
    end

    it "never caches a hostname the gate rejects" do
      described_class.parse("localhost")
      described_class.parse("127.0.0.1")

      expect(cache_size).to eq(0)
    end

    it "keeps answering correctly when many threads parse at once" do
      hosts = {
        "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" =>
          {identifier: "orders-db", endpoint_type: "instance", region: "us-east-1"},
        "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" =>
          {identifier: "orders", endpoint_type: "cluster-ro", region: "eu-west-1"},
        "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk" =>
          {identifier: "isoe-db", endpoint_type: "instance", region: "eu-isoe-west-1"},
        "not-really.rds.example.com" => nil,
        "localhost" => nil,
      }

      threads = 8.times.map do |thread|
        Thread.new do
          200.times do |i|
            # Each thread also writes endpoints no other thread asks for, so reads and
            # writes genuinely overlap rather than settling after the first iteration,
            # and the 1_600 distinct endpoints together drive eviction throughout.
            described_class.parse("t#{thread}db#{i}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com")

            hosts.each { |host, expected| expect(described_class.parse(host)).to eq(expected) }
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
      expect(cache_size).to be <= 512
    end
  end

  # The gate in front of the parser exists so that a database that is not on RDS -- the
  # common case -- costs nothing per span. These pin that: a regression that reintroduces
  # a `strip`, a downcased copy, or a `MatchData`-building match on this path shows up as
  # allocations.
  describe "allocations" do
    let(:iterations) { 1_000 }

    [
      "localhost",
      "127.0.0.1",
      "db.internal.example.com",
      "my-service-db.prod.svc.cluster.local",
      "/var/run/postgresql/.s.PGSQL.5432",
    ].each do |host|
      it "allocates nothing parsing #{host.inspect}" do
        expect(allocations_for(iterations) { described_class.parse(host) }).to eq(0)
      end
    end

    [
      "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
      "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com",
      "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk",
      "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com:5432",
    ].each do |host|
      it "allocates nothing re-parsing the known endpoint #{host.inspect}" do
        expect(allocations_for(iterations) { described_class.parse(host) }).to eq(0)
      end
    end

    it "allocates nothing annotating a span whose host is not on RDS" do
      span = Datadog::Tracing::SpanOperation.new("fake")
      # Held in a local on purpose: a string literal inside the measured block would be
      # allocated on every iteration and counted against the parser.
      host = "db.internal.example.com"

      expect(allocations_for(iterations) { described_class.annotate!(span, host) }).to eq(0)
    end
  end

  describe ".annotate!" do
    subject(:annotate!) { described_class.annotate!(span, hostname) }

    let(:span) { Datadog::Tracing::SpanOperation.new("fake") }

    def rds_tags
      {
        identifier: span.get_tag(ext::TAG_IDENTIFIER),
        endpoint_type: span.get_tag(ext::TAG_ENDPOINT_TYPE),
        region: span.get_tag(ext::TAG_REGION),
        dbinstanceidentifier: span.get_tag(ext::TAG_DB_INSTANCE_IDENTIFIER),
        dbclusteridentifier: span.get_tag(ext::TAG_DB_CLUSTER_IDENTIFIER),
      }
    end

    context "with an instance endpoint" do
      let(:hostname) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "tags the instance identifier and never the cluster identifier" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "orders-db",
          endpoint_type: "instance",
          region: "us-east-1",
          dbinstanceidentifier: "orders-db",
          dbclusteridentifier: nil
        )
      end
    end

    context "with a cluster endpoint" do
      let(:hostname) { "orders.cluster-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "tags the cluster identifier and never claims a writer instance" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "orders",
          endpoint_type: "cluster",
          region: "us-east-1",
          dbinstanceidentifier: nil,
          dbclusteridentifier: "orders"
        )
      end
    end

    context "with a reader endpoint" do
      let(:hostname) { "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" }

      it "tags the cluster identifier and never an instance identifier" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "orders",
          endpoint_type: "cluster-ro",
          region: "eu-west-1",
          dbinstanceidentifier: nil,
          dbclusteridentifier: "orders"
        )
      end
    end

    context "with a custom cluster endpoint" do
      let(:hostname) { "analytics.cluster-custom-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "tags only the endpoint name, because the cluster is not named in the hostname" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "analytics",
          endpoint_type: "cluster-custom",
          region: "us-east-1",
          dbinstanceidentifier: nil,
          dbclusteridentifier: nil
        )
      end
    end

    context "with a proxy endpoint" do
      let(:hostname) { "orders-proxy.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "tags only the proxy name, because the target is not named in the hostname" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "orders-proxy",
          endpoint_type: "proxy",
          region: "us-east-1",
          dbinstanceidentifier: nil,
          dbclusteridentifier: nil
        )
      end
    end

    context "with an endpoint outside the commercial partition" do
      let(:hostname) { "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk" }

      it "tags the same way as any other partition" do
        annotate!

        expect(rds_tags).to eq(
          identifier: "isoe-db",
          endpoint_type: "instance",
          region: "eu-isoe-west-1",
          dbinstanceidentifier: "isoe-db",
          dbclusteridentifier: nil
        )
      end
    end

    context "with a host that is not an RDS endpoint" do
      [
        "db.internal.example.com",
        "localhost",
        # a Region that its DNS suffix does not serve
        "iso-db.cdbfa1b2c3d4.us-iso-east-1.rds.amazonaws.com",
        # endpoint forms that are deliberately not read
        "global-orders.global-cdbfa1b2c3d4.global.rds.amazonaws.com",
        "readonly.endpoint.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
        "orders.shardgrp-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com",
      ].each do |host|
        context "with #{host}" do
          let(:hostname) { host }

          it "adds no tags at all" do
            annotate!

            expect(rds_tags.values).to all(be_nil)
            expect(span.tags).to be_empty
          end
        end
      end
    end

    context "with the account label in the hostname" do
      let(:hostname) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

      it "never emits the account-specific label in any tag" do
        annotate!

        expect(span.tags.values).to all(satisfy { |value| !value.to_s.include?("cdbfa1b2c3d4") })
      end
    end
  end
end
