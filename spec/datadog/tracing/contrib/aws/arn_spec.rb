# frozen_string_literal: true

require "datadog/tracing/contrib/aws/arn"

RSpec.describe Datadog::Tracing::Contrib::Aws::Arn do
  describe ".parse" do
    subject(:parsed) { described_class.parse(value) }

    context "with a bare-resource ARN" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic-name" }

      it "exposes every field" do
        expect(parsed.partition).to eq("aws")
        expect(parsed.service).to eq("sns")
        expect(parsed.region).to eq("us-west-2")
        expect(parsed.account_id).to eq("123456789012")
        expect(parsed.resource).to eq("my-topic-name")
      end
    end

    context "with a colon-delimited resource" do
      let(:value) { "arn:aws:states:us-east-1:123456789012:execution:my-machine:my-execution" }

      it "keeps every colon after the account in the resource" do
        expect(parsed.resource).to eq("execution:my-machine:my-execution")
      end
    end

    context "with a GovCloud ARN" do
      let(:value) { "arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:my-function" }

      it "accepts the partition and Region" do
        expect(parsed.partition).to eq("aws-us-gov")
        expect(parsed.region).to eq("us-gov-west-1")
        expect(parsed.account_id).to eq("123456789012")
      end
    end

    context "with a China ARN" do
      let(:value) { "arn:aws-cn:kinesis:cn-north-1:123456789012:stream/my-stream" }

      it "accepts the partition and Region" do
        expect(parsed.partition).to eq("aws-cn")
        expect(parsed.region).to eq("cn-north-1")
      end
    end

    context "with an ISO partition ARN" do
      let(:value) { "arn:aws-iso-b:sns:us-isob-east-1:123456789012:my-topic" }

      it "accepts the partition and Region" do
        expect(parsed.partition).to eq("aws-iso-b")
        expect(parsed.region).to eq("us-isob-east-1")
      end
    end

    context "when the ARN omits the Region and account" do
      let(:value) { "arn:aws:s3:::my-bucket" }

      it "reports them as nil rather than guessing" do
        expect(parsed.region).to be_nil
        expect(parsed.account_id).to be_nil
        expect(parsed.resource).to eq("my-bucket")
      end
    end

    context "when the ARN omits only the Region" do
      let(:value) { "arn:aws:dynamodb::123456789012:global-table/MyTable" }

      it "keeps the account and reports no Region" do
        expect(parsed.region).to be_nil
        expect(parsed.account_id).to eq("123456789012")
        expect(parsed.resource).to eq("global-table/MyTable")
      end
    end

    context "with a malformed value" do
      [
        ["nil", nil],
        ["a symbol", :"arn:aws:sns:us-west-2:123456789012:my-topic"],
        ["a non-string", 1234],
        ["an empty string", ""],
        ["a bare name", "my-table-name"],
        ["a name that merely mentions arn", "streamArn"],
        ["a leading-space ARN", " arn:aws:sns:us-west-2:123456789012:my-topic"],
        ["the prefix alone", "arn"],
        ["the prefix with a colon", "arn:"],
        ["a truncated ARN", "arn:aws"],
        ["an ARN with five segments", "arn:aws:sns:us-west-2:123456789012"],
        ["an ARN with an empty resource", "arn:aws:sns:us-west-2:123456789012:"],
        ["an ARN with an empty partition", "arn::sns:us-west-2:123456789012:my-topic"],
        ["an ARN with an empty service", "arn:aws::us-west-2:123456789012:my-topic"],
        ["a non-AWS partition", "arn:gcp:sns:us-west-2:123456789012:my-topic"],
        ["an upper-case partition", "arn:AWS:sns:us-west-2:123456789012:my-topic"],
        ["a non-Region Region", "arn:aws:sns:not-a-region:123456789012:my-topic"],
        ["an upper-case Region", "arn:aws:sns:US-WEST-2:123456789012:my-topic"],
        ["a short account id", "arn:aws:sns:us-west-2:12345:my-topic"],
        ["a non-numeric account id", "arn:aws:sns:us-west-2:not-an-account:my-topic"],
        ["a too-long account id", "arn:aws:sns:us-west-2:1234567890123:my-topic"],
      ].each do |description, malformed|
        context "that is #{description}" do
          let(:value) { malformed }

          it "answers nil without raising" do
            expect { parsed }.not_to raise_error
            expect(parsed).to be_nil
          end
        end
      end
    end

    describe "with an encoding a comparison cannot read" do
      [
        [
          "an invalid byte in the resource",
          "arn:aws:sns:us-west-2:123456789012:my-\xFFtopic",
        ],
        [
          "an invalid byte in the Region",
          "arn:aws:sns:us-\xFFwest-2:123456789012:my-topic",
        ],
        [
          "an invalid byte in the partition",
          "arn:aw\xFFs:sns:us-west-2:123456789012:my-topic",
        ],
        [
          "an invalid byte in the account id",
          "arn:aws:sns:us-west-2:12345678901\xFF:my-topic",
        ],
        [
          "an invalid byte in the service",
          "arn:aws:s\xFFns:us-west-2:123456789012:my-topic",
        ],
        [
          "nothing but an invalid byte",
          "\xFF",
        ],
      ].each do |description, bytes|
        context "that has #{description}" do
          let(:value) { bytes.dup.force_encoding(::Encoding::UTF_8) }

          it "is not valid in its declared encoding" do
            expect(value.valid_encoding?).to be(false)
          end

          it "answers nil without raising" do
            expect { parsed }.not_to raise_error
            expect(parsed).to be_nil
          end
        end
      end

      context "that is a well-formed ARN in a non ASCII-compatible encoding" do
        let(:value) do
          "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable".encode(::Encoding::UTF_16LE)
        end

        it "answers nil without raising" do
          expect(value.valid_encoding?).to be(true)
          expect(value.encoding.ascii_compatible?).to be(false)
          expect { parsed }.not_to raise_error
          expect(parsed).to be_nil
        end
      end

      context "that is a well-formed ARN in a binary encoding" do
        let(:value) do
          (+"arn:aws:dynamodb:us-east-1:123456789012:table/MyTable").force_encoding(::Encoding::BINARY)
        end

        it "is parsed, because every byte is valid and ASCII-compatible" do
          expect(parsed.service).to eq("dynamodb")
          expect(parsed.resource).to eq("table/MyTable")
        end
      end
    end
  end

  describe ".scannable?" do
    subject(:scannable) { described_class.scannable?(value) }

    context "with an ASCII string" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic" }

      it { is_expected.to be(true) }
    end

    context "with a non-string" do
      let(:value) { 1234 }

      it { is_expected.to be(false) }
    end

    context "with nil" do
      let(:value) { nil }

      it { is_expected.to be(false) }
    end

    context "with a string whose bytes are invalid in its encoding" do
      let(:value) { (+"my-\xFFtopic").force_encoding(::Encoding::UTF_8) }

      it { is_expected.to be(false) }
    end

    context "with a string in a non ASCII-compatible encoding" do
      let(:value) { "my-topic".encode(::Encoding::UTF_16LE) }

      it { is_expected.to be(false) }
    end
  end

  describe ".arn_like?" do
    subject(:arn_like) { described_class.arn_like?(value) }

    context "with a well-formed ARN" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic" }

      it { is_expected.to be(true) }
    end

    context "with a malformed value that still opens with the ARN prefix" do
      let(:value) { "arn:not-an-arn" }

      it { is_expected.to be(true) }
    end

    context "with an ARN-prefixed value whose bytes are invalid in its encoding" do
      let(:value) { (+"arn:aws:sns:us-west-2:123456789012:my-\xFFtopic").force_encoding("UTF-8") }

      it { is_expected.to be(true) }
    end

    context "with a bare name" do
      let(:value) { "my-topic" }

      it { is_expected.to be(false) }
    end

    context "with a non-string" do
      let(:value) { 1234 }

      it { is_expected.to be(false) }
    end

    context "with nil" do
      let(:value) { nil }

      it { is_expected.to be(false) }
    end

    context "with a non ASCII-compatible encoding whose bytes do not match the prefix" do
      let(:value) { "arn:".encode(::Encoding::UTF_16LE) }

      it { is_expected.to be(false) }
    end
  end

  describe "#resource_name" do
    subject(:resource_name) { described_class.parse(value).resource_name(service, format) }

    let(:service) { "dynamodb" }
    let(:format) { %r{\Atable/(?<name>[^:/]+)\z} }

    context "with a matching service and resource" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }

      it { is_expected.to eq("MyTable") }
    end

    context "with a mismatched service" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }
      let(:service) { "kinesis" }

      it { is_expected.to be_nil }
    end

    [
      ["a different separator", "arn:aws:dynamodb:us-east-1:123456789012:table:MyTable"],
      ["a trailing separator", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/"],
      ["a nested resource", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/index/MyIndex"],
      ["no id", "arn:aws:dynamodb:us-east-1:123456789012:table/"],
      ["no Region", "arn:aws:dynamodb::123456789012:table/MyTable"],
      ["no account", "arn:aws:dynamodb:us-east-1::table/MyTable"],
    ].each do |description, malformed|
      context "with #{description}" do
        let(:value) { malformed }

        it { is_expected.to be_nil }
      end
    end
  end
end
