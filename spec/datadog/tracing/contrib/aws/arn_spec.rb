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

      it "reports a bare resource" do
        expect(parsed).to be_bare_resource
        expect(parsed.resource_segments).to eq(["my-topic-name"])
      end
    end

    context "with a slash-delimited resource" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }

      it "splits the resource into type and id" do
        expect(parsed.resource_segments).to eq(["table", "MyTable"])
        expect(parsed).not_to be_bare_resource
      end
    end

    context "with a colon-delimited resource" do
      let(:value) { "arn:aws:states:us-east-1:123456789012:execution:my-machine:my-execution" }

      it "splits every resource segment" do
        expect(parsed.resource).to eq("execution:my-machine:my-execution")
        expect(parsed.resource_segments).to eq(["execution", "my-machine", "my-execution"])
        expect(parsed).not_to be_bare_resource
      end
    end

    context "with a mixed-delimiter resource" do
      let(:value) { "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream/consumer/my-consumer/1693526402" }

      it "splits on both delimiters" do
        expect(parsed.resource_segments).to eq(
          ["stream", "my-stream", "consumer", "my-consumer", "1693526402"]
        )
      end
    end

    # A caller that requires a resource of exactly N segments has to be able to
    # tell `table/MyTable` from `table/MyTable/`, so a trailing separator is
    # kept as an empty segment rather than dropped.
    context "with a resource ending in a separator" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/" }

      it "keeps the trailing empty segment" do
        expect(parsed.resource_segments).to eq(["table", "MyTable", ""])
        expect(parsed).not_to be_bare_resource
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
      # A partition-global ARN form. Parsing it says nothing about which
      # request parameters accept it; {Service::DynamoDB} deliberately does
      # not read `global-table` as a `TableName`.
      let(:value) { "arn:aws:dynamodb::123456789012:global-table/MyTable" }

      it "keeps the account and reports no Region" do
        expect(parsed.region).to be_nil
        expect(parsed.account_id).to eq("123456789012")
        expect(parsed.resource_segments).to eq(["global-table", "MyTable"])
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

    # A request parameter arrives from the caller, so a value whose bytes are
    # not valid in its own encoding, or whose encoding cannot be compared with
    # the ASCII patterns an ARN is matched against, is reachable with ordinary
    # input. Both raise from `String#start_with?` or `Regexp#match?` rather
    # than answering false, which is why they are rejected up front.
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
          expect(parsed.resource_segments).to eq(["table", "MyTable"])
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

  describe "#typed_resource_id" do
    subject(:resource_id) { described_class.parse(value).typed_resource_id(service, resource_types) }

    context "with a matching service and resource type" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }
      let(:service) { "dynamodb" }
      let(:resource_types) { ["table"] }

      it { is_expected.to eq("MyTable") }
    end

    context "with one of several accepted resource types" do
      let(:value) { "arn:aws:states:us-east-1:123456789012:express:MyStateMachine:MyExecution:1234-5678" }
      let(:service) { "states" }
      let(:resource_types) { ["execution", "express"] }

      it { is_expected.to eq("MyStateMachine") }
    end

    context "with a trailing resource id" do
      let(:value) { "arn:aws:lambda:us-east-1:123456789012:function:my-function:PROD" }
      let(:service) { "lambda" }
      let(:resource_types) { ["function"] }

      it "ignores the segments after the id" do
        is_expected.to eq("my-function")
      end
    end

    context "with a mismatched service" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }
      let(:service) { "kinesis" }
      let(:resource_types) { ["table"] }

      it { is_expected.to be_nil }
    end

    context "with a mismatched resource type" do
      let(:value) { "arn:aws:lambda:us-east-1:123456789012:layer:my-layer:1" }
      let(:service) { "lambda" }
      let(:resource_types) { ["function"] }

      it { is_expected.to be_nil }
    end

    context "with a bare resource" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic" }
      let(:service) { "sns" }
      let(:resource_types) { ["topic"] }

      it { is_expected.to be_nil }
    end

    context "with a resource type but no id" do
      let(:value) { "arn:aws:dynamodb:us-east-1:123456789012:table/" }
      let(:service) { "dynamodb" }
      let(:resource_types) { ["table"] }

      it { is_expected.to be_nil }
    end
  end

  describe "#bare_resource_id" do
    subject(:resource_id) { described_class.parse(value).bare_resource_id(service) }

    let(:service) { "sns" }

    context "with a bare resource" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic-name" }

      it { is_expected.to eq("my-topic-name") }
    end

    context "with a slash-delimited resource" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:endpoint/APNS/my-app/1234-5678" }

      it { is_expected.to be_nil }
    end

    context "with a colon-delimited resource" do
      let(:value) { "arn:aws:sns:us-west-2:123456789012:my-topic:8a21d249-4329" }

      it { is_expected.to be_nil }
    end

    context "with a mismatched service" do
      let(:value) { "arn:aws:sqs:us-west-2:123456789012:my-queue" }

      it { is_expected.to be_nil }
    end
  end
end
