# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/sns"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::SNS do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:sns) { described_class.new }
  let(:ext) { Datadog::Tracing::Contrib::Aws::Ext }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with topic_arn provided" do
    let(:topic_arn) { "arn:aws:sns:us-west-2:123456789012:my-topic-name" }
    let(:params) { {topic_arn: topic_arn} }

    it "sets the topic_name and aws_account based on the topic_arn" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "my-topic-name")
    end

    it "sets the aws.topic.name and aws.topic.arn tags" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_NAME, "my-topic-name")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, topic_arn)
    end
  end

  context "with name provided" do
    let(:params) { {name: "my-topic-name"} }

    it "sets the topic_name based on the provided name" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "my-topic-name")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_NAME, "my-topic-name")
    end

    it "reports no ARN and no account" do
      sns.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with neither topic_arn nor name provided" do
    it "sets the topic_name to nil" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, nil)
    end

    it "does not set the aws.topic.name tag" do
      sns.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_NAME, anything)
    end
  end

  context "with a topic_arn and a conflicting name" do
    let(:topic_arn) { "arn:aws:sns:us-west-2:123456789012:arn-topic" }
    let(:params) { {topic_arn: topic_arn, name: "param-topic"} }

    it "prefers the ARN, which carries the full identity" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "arn-topic")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, topic_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a GovCloud topic ARN" do
    let(:topic_arn) { "arn:aws-us-gov:sns:us-gov-west-1:123456789012:my-topic-name" }
    let(:params) { {topic_arn: topic_arn} }

    it "resolves the topic name, ARN and account" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "my-topic-name")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, topic_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a China topic ARN" do
    let(:topic_arn) { "arn:aws-cn:sns:cn-north-1:123456789012:my-topic-name" }
    let(:params) { {topic_arn: topic_arn} }

    it "resolves the topic name, ARN and account" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "my-topic-name")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, topic_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  # `Publish` takes either a topic ARN or a mobile platform endpoint ARN in
  # `TargetArn`. An endpoint is not a topic, so it must never reach the topic
  # tags.
  context "with a mobile platform endpoint target_arn" do
    let(:params) { {target_arn: "arn:aws:sns:us-west-2:123456789012:endpoint/APNS/my-app/1234-5678"} }

    it "claims no topic identity" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_NAME, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with a topic target_arn" do
    let(:params) { {target_arn: "arn:aws:sns:us-west-2:123456789012:my-topic-name"} }

    it "leaves the topic tags to topic_arn" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
    end
  end

  context "with a subscription ARN provided as topic_arn" do
    let(:topic_arn) { "arn:aws:sns:us-west-2:123456789012:my-topic:8a21d249-4329" }
    let(:params) { {topic_arn: topic_arn} }

    it "claims no topic identity" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with a malformed topic_arn" do
    let(:params) { {topic_arn: "arn:aws:sns:us-west-2:oops:my-topic", name: "my-topic-name"} }

    it "falls back to the explicit name and invents no account" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "my-topic-name")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  # The legacy tag keeps its pre-existing unconditional write, which
  # `peer.service` resolution depends on. `aws.topic.name` is new, and an
  # empty one would publish a target identity the request never named.
  context "with an empty name" do
    let(:params) { {name: ""} }

    it "writes the legacy tag but not the new one" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, "")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_NAME, anything)
    end
  end

  context "with another service's ARN provided as topic_arn" do
    let(:params) { {topic_arn: "arn:aws:sqs:us-west-2:123456789012:my-queue"} }

    it "claims no topic identity" do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TOPIC_NAME, nil)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TOPIC_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end
end
