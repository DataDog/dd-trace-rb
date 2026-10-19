# frozen_string_literal: true

require "aws-sdk"
require "datadog/tracing/contrib/aws/parsed_context"
require "datadog/tracing/contrib/aws/service/base"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Base do
  subject(:base) { described_class.new }

  let(:context) { instance_double(Datadog::Tracing::Contrib::Aws::ParsedContext) }

  describe "#aws_confirmed_response?" do
    subject(:aws_confirmed_response?) { base.send(:aws_confirmed_response?, context) }

    let(:status_code) { 200 }
    let(:host) { "my-bucket-name.s3.us-east-1.amazonaws.com" }

    before do
      allow(context).to receive(:safely).with(:status_code).and_return(status_code)
      allow(context).to receive(:safely).with(:host).and_return(host)
    end

    it { is_expected.to be true }

    describe "endpoint ownership" do
      {
        "a virtual-hosted commercial endpoint" => "my-bucket-name.s3.us-east-1.amazonaws.com",
        "a path-style commercial endpoint" => "s3.us-east-1.amazonaws.com",
        "the global endpoint" => "s3.amazonaws.com",
        "a dual-stack endpoint" => "s3.dualstack.us-east-1.amazonaws.com",
        "a FIPS endpoint" => "s3-fips.us-east-1.amazonaws.com",
        "an access point endpoint" => "ap-123456789012.s3-accesspoint.us-east-1.amazonaws.com",
        "an S3 Express endpoint" => "bucket--use1-az5--x-s3.s3express-use1-az5.us-east-1.amazonaws.com",
        "an Outposts endpoint" => "s3-outposts.us-east-1.amazonaws.com",
        "a VPC endpoint" => "bucket.vpce-0a1b-c2d3.s3.us-east-1.vpce.amazonaws.com",
        "a DynamoDB endpoint" => "dynamodb.us-east-1.amazonaws.com",
        "a China endpoint" => "s3.cn-north-1.amazonaws.com.cn",
        "a GovCloud endpoint" => "s3.us-gov-west-1.amazonaws.com",
        "an ISO endpoint" => "s3.us-iso-east-1.c2s.ic.gov",
        "an ISO-B endpoint" => "s3.us-isob-east-1.sc2s.sgov.gov",
        "an EU sovereign endpoint" => "s3.eusc-de-east-1.amazonaws.eu",
        "a new dual-stack endpoint" => "s3.us-east-1.api.aws",
        "a trailing-dot fully qualified host" => "s3.us-east-1.amazonaws.com.",
        "a mixed-case host" => "S3.US-East-1.AmazonAWS.CoM",
      }.each do |description, aws_host|
        context "with #{description}" do
          let(:host) { aws_host }

          it { is_expected.to be true }
        end
      end

      {
        "a LocalStack endpoint" => "localhost",
        "a loopback address" => "127.0.0.1",
        "a MinIO endpoint" => "minio.internal",
        "a DynamoDB Local endpoint" => "dynamodb.internal.example.com",
        "a self-hosted gateway" => "s3.storage.example.com",
        "a Ceph endpoint" => "rgw.ceph.svc.cluster.local",
        "a suffix lookalike domain" => "s3.us-east-1.amazonaws.com.example.net",
        "a domain missing the dot boundary" => "notamazonaws.com",
        "a bare partition suffix" => "amazonaws.com",
        "an empty host" => "",
        "a non-string host" => :host,
        "an unavailable host" => nil,
      }.each do |description, other_host|
        context "with #{description}" do
          let(:host) { other_host }

          it { is_expected.to be false }
        end
      end

      context "when the partition list is unavailable" do
        before { allow(described_class).to receive(:aws_dotted_dns_suffixes).and_return([].freeze) }

        it { is_expected.to be false }
      end
    end

    describe "response success" do
      [200, 201, 204, 299].each do |code|
        context "when the response status is #{code}" do
          let(:status_code) { code }

          it { is_expected.to be true }
        end
      end

      [100, 199, 300, 301, 400, 403, 404, 500, 503].each do |code|
        context "when the response status is #{code}" do
          let(:status_code) { code }

          it { is_expected.to be false }
        end
      end

      context "when the status code is unavailable" do
        let(:status_code) { nil }

        it { is_expected.to be false }
      end

      context "when the status code is a string" do
        let(:status_code) { "200" }

        it { is_expected.to be false }
      end
    end

    context "when the response failed from an AWS endpoint" do
      let(:status_code) { 403 }

      it { is_expected.to be false }
    end

    context "when the response succeeded from a non-AWS endpoint" do
      let(:host) { "localhost" }

      it { is_expected.to be false }
    end
  end

  describe ".aws_dotted_dns_suffixes" do
    # The memoized list and the report gate both live on the class for the
    # life of the process, so these examples have to put back exactly what
    # they found. Written with an explicit `begin`/`ensure` because a bare
    # `ensure` inside a block needs Ruby 2.6, and the `aws` contrib is
    # supported from 2.5.
    around do |example|
      only_once = described_class.const_get(:DNS_SUFFIX_FAILURE_ONLY_ONCE)
      memo_was_set = described_class.instance_variable_defined?(:@aws_dotted_dns_suffixes)
      memoized = described_class.instance_variable_get(:@aws_dotted_dns_suffixes)
      only_once_had_run = only_once.ran?

      described_class.remove_instance_variable(:@aws_dotted_dns_suffixes) if memo_was_set
      only_once.send(:reset_ran_once_state_for_tests)

      begin
        example.run
      ensure
        if memo_was_set
          described_class.instance_variable_set(:@aws_dotted_dns_suffixes, memoized)
        elsif described_class.instance_variable_defined?(:@aws_dotted_dns_suffixes)
          described_class.remove_instance_variable(:@aws_dotted_dns_suffixes)
        end

        only_once.send(:reset_ran_once_state_for_tests)
        only_once.run { nil } if only_once_had_run
      end
    end

    it "covers every partition's standard and dual-stack suffix" do
      expect(described_class.aws_dotted_dns_suffixes)
        .to include(".amazonaws.com", ".amazonaws.com.cn", ".c2s.ic.gov", ".api.aws")
    end

    # The leading dot is what makes the caller's `end_with?` a dot-boundary
    # match, and precomputing it is what keeps the hot path allocation-free.
    it "stores each suffix with its leading dot already attached" do
      suffixes = described_class.aws_dotted_dns_suffixes

      expect(suffixes).to all(start_with("."))
      expect(suffixes).to all(be_frozen)
      expect(suffixes).not_to include("amazonaws.com")
    end

    it "is frozen and memoized once it has been read" do
      expect(described_class.aws_dotted_dns_suffixes).to be_frozen
      expect(described_class.aws_dotted_dns_suffixes).to be(described_class.aws_dotted_dns_suffixes)
    end

    # Memoizing a failure would disable owner tagging for the rest of the
    # process, and the failure can be transient, so only a non-empty read is
    # kept. The report is gated to once per process because the read is retried
    # on every subsequent span.
    shared_examples "an observable, retried failure" do |expected_log|
      before do
        allow(Datadog.logger).to receive(:warn)
        allow(Datadog::Core::Telemetry::Logger).to receive(:error)
        allow(Datadog::Core::Telemetry::Logger).to receive(:report)
      end

      it "returns an empty list without memoizing it" do
        expect(described_class.aws_dotted_dns_suffixes).to eq([])
        expect(described_class.aws_dotted_dns_suffixes).to eq([])

        expect(described_class.instance_variable_defined?(:@aws_dotted_dns_suffixes)).to be false
      end

      it "logs and reports the failure exactly once" do
        described_class.aws_dotted_dns_suffixes
        described_class.aws_dotted_dns_suffixes

        expect(Datadog.logger).to have_received(:warn).with(expected_log).once
      end

      it "loads the suffixes once the partition list can be read again" do
        expect(described_class.aws_dotted_dns_suffixes).to eq([])

        allow(::Aws::Partitions).to receive(:each).and_call_original

        expect(described_class.aws_dotted_dns_suffixes).to include(".amazonaws.com")
        expect(described_class.instance_variable_defined?(:@aws_dotted_dns_suffixes)).to be true
      end
    end

    context "when reading the partition list raises" do
      before { allow(::Aws::Partitions).to receive(:each).and_raise(ArgumentError, "partitions unreadable") }

      include_examples "an observable, retried failure", /ArgumentError: partitions unreadable/

      it "reports the exception to telemetry" do
        allow(Datadog.logger).to receive(:warn)
        allow(Datadog::Core::Telemetry::Logger).to receive(:report)

        described_class.aws_dotted_dns_suffixes
        described_class.aws_dotted_dns_suffixes

        expect(Datadog::Core::Telemetry::Logger).to have_received(:report).with(
          an_instance_of(ArgumentError),
          level: :warn,
          description: described_class.const_get(:DNS_SUFFIX_FAILURE_DESCRIPTION),
        ).once
      end
    end

    context "when the partition list reports no suffix" do
      before { allow(::Aws::Partitions).to receive(:each) }

      include_examples "an observable, retried failure", /Aws::Partitions reported no DNS suffix/

      it "reports the condition to telemetry" do
        allow(Datadog.logger).to receive(:warn)
        allow(Datadog::Core::Telemetry::Logger).to receive(:error)

        described_class.aws_dotted_dns_suffixes
        described_class.aws_dotted_dns_suffixes

        expect(Datadog::Core::Telemetry::Logger)
          .to have_received(:error)
          .with(described_class.const_get(:DNS_SUFFIX_FAILURE_DESCRIPTION))
          .once
      end
    end

    # `Partition#metadata` is newer than the oldest `aws-partitions` this gem
    # runs against. A partition without it is skipped instead of raising
    # NoMethodError, and skipping all of them reads as no suffix, which fails
    # closed rather than matching every host.
    context "when the partition list predates Partition#metadata" do
      let(:legacy_partition) { double("aws-partitions Partition without #metadata") }

      before { allow(::Aws::Partitions).to receive(:each).and_yield(legacy_partition) }

      include_examples "an observable, retried failure", /Aws::Partitions reported no DNS suffix/

      it "skips the partition instead of raising" do
        allow(Datadog.logger).to receive(:warn)
        allow(Datadog::Core::Telemetry::Logger).to receive(:error)

        expect(legacy_partition).not_to respond_to(:metadata)
        expect { described_class.aws_dotted_dns_suffixes }.not_to raise_error
        expect(described_class.aws_dotted_dns_suffixes).to eq([])
      end

      it "still reads the partitions that do carry metadata" do
        modern_partition = double(
          "aws-partitions Partition with #metadata",
          metadata: {"dnsSuffix" => "amazonaws.com", "dualStackDnsSuffix" => "api.aws"},
        )
        allow(::Aws::Partitions).to receive(:each).and_yield(legacy_partition).and_yield(modern_partition)

        expect(described_class.aws_dotted_dns_suffixes).to eq([".amazonaws.com", ".api.aws"])
      end
    end
  end

  describe "#add_owner_tags" do
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }

    # Only DynamoDB and S3 override this. Every other handler inherits the
    # no-op, so moving the response gate onto `Base` does not start tagging
    # owners anywhere new.
    it "is a no-op" do
      expect(base.add_owner_tags(span, {expected_bucket_owner: "123456789012"}, context)).to be_nil
    end
  end
end
