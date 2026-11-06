# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/kinesis"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Kinesis do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:kinesis) { described_class.new }
  let(:ext) { Datadog::Tracing::Contrib::Aws::Ext }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with stream_arn provided" do
    let(:stream_arn) { "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream" }
    let(:params) { {stream_arn: stream_arn} }

    it "sets the stream_name and aws_account based on the stream_arn" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
    end

    it "sets the aws.stream.name and aws.stream.arn tags" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, "my-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, stream_arn)
    end
  end

  context "with stream_name provided" do
    let(:params) { {stream_name: "my-stream"} }

    it "sets the stream_name based on the provided stream_name" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, "my-stream")
    end

    it "reports no ARN and no account" do
      kinesis.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with neither stream_arn nor stream_name provided" do
    it "sets the stream_name to nil" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, nil)
    end

    it "does not set the aws.stream.name tag" do
      kinesis.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, anything)
    end
  end

  context "with a stream_arn and a conflicting stream_name" do
    let(:stream_arn) { "arn:aws:kinesis:us-east-1:123456789012:stream/arn-stream" }
    let(:params) { {stream_arn: stream_arn, stream_name: "param-stream"} }

    it "prefers the ARN, which carries the full identity" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "arn-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, "arn-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a consumer-qualified stream ARN" do
    let(:stream_arn) do
      "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream/consumer/my-consumer/1693526402"
    end
    let(:params) { {stream_arn: stream_arn} }

    it "reports the stream, not the consumer" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, "my-stream")
    end
  end

  context "with a GovCloud stream ARN" do
    let(:stream_arn) { "arn:aws-us-gov:kinesis:us-gov-east-1:123456789012:stream/my-stream" }
    let(:params) { {stream_arn: stream_arn} }

    it "resolves the stream name, ARN and account" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, stream_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a China stream ARN" do
    let(:stream_arn) { "arn:aws-cn:kinesis:cn-northwest-1:123456789012:stream/my-stream" }
    let(:params) { {stream_arn: stream_arn} }

    it "resolves the stream name, ARN and account" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, stream_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a malformed stream_arn" do
    let(:params) { {stream_arn: "streamArn"} }

    it "claims neither a name, an ARN nor an account" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with a malformed stream_arn and a stream_name" do
    let(:params) { {stream_arn: "arn:aws:kinesis:us-east-1:123456789012:oops/my-stream", stream_name: "my-stream"} }

    it "falls back to the explicit stream_name" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "my-stream")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  # The legacy tag keeps its pre-existing unconditional write, which
  # `peer.service` resolution depends on. `aws.stream.name` is new, and an
  # empty one would publish a target identity the request never named.
  context "with an empty stream_name" do
    let(:params) { {stream_name: ""} }

    it "writes the legacy tag but not the new one" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, "")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_NAME, anything)
    end
  end

  context "with another service's ARN provided as stream_arn" do
    let(:params) { {stream_arn: "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable"} }

    it "claims no stream identity" do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STREAM_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STREAM_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end
end
