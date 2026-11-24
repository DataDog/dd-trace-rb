# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/core/utils/base64_codec"
require "json"
require "aws-sdk"

require "datadog"
require "datadog/tracing/contrib/aws/patcher"

RSpec.describe "AWS Data Streams instrumentation" do
  let(:data_streams_enabled) { true }
  let(:queue_url) { "https://sqs.us-east-1.amazonaws.com/123456789012/orders" }
  let(:topic_arn) { "arn:aws:sns:us-east-1:123456789012:events" }
  let(:sqs) { Aws::SQS::Client.new(stub_responses: true) }
  let(:sns) { Aws::SNS::Client.new(stub_responses: true) }

  before do
    skip_if_libdatadog_not_supported

    Datadog.configure do |c|
      c.tracing.instrument :aws
      c.data_streams.enabled = data_streams_enabled
    end
    Datadog::DataStreams.pathway_context = nil
  end

  around do |example|
    Datadog.registry[:aws].reset_configuration!
    example.run
    Datadog.registry[:aws].reset_configuration!
  end

  def sent_params(client, operation)
    client.api_requests.reverse.find { |r| r[:operation_name] == operation }[:params]
  end

  def pathway_from(carrier_json)
    JSON.parse(carrier_json).fetch("dd-pathway-ctx-base64")
  end

  def produced_hash(encoded)
    Datadog::DataStreams::PathwayContext.decode_b64(encoded).hash
  end

  def consume_messages(messages)
    sqs.stub_responses(:receive_message, messages: messages)
    sqs.receive_message(queue_url: queue_url)
    Datadog::DataStreams.pathway_context
  end

  describe "SQS send_message" do
    it "writes the pathway into a String _datadog attribute" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")

      attribute = sent_params(sqs, :send_message)[:message_attributes]["_datadog"]
      expect(attribute[:data_type]).to eq("String")
      expect(produced_hash(pathway_from(attribute[:string_value]))).to be > 0
    end

    it "keeps the caller's attributes" do
      sqs.send_message(
        queue_url: queue_url,
        message_body: "hi",
        message_attributes: {"tenant" => {data_type: "String", string_value: "a"}},
      )

      expect(sent_params(sqs, :send_message)[:message_attributes].keys).to contain_exactly("tenant", "_datadog")
    end

    it "adds the pathway to an existing _datadog JSON attribute" do
      sqs.send_message(
        queue_url: queue_url,
        message_body: "hi",
        message_attributes: {"_datadog" => {data_type: "String", string_value: '{"x-datadog-trace-id":"1"}'}},
      )

      carrier = JSON.parse(sent_params(sqs, :send_message)[:message_attributes]["_datadog"][:string_value])
      expect(carrier).to include("x-datadog-trace-id" => "1", "dd-pathway-ctx-base64" => kind_of(String))
    end

    it "leaves the message alone when it already has 10 attributes" do
      attributes = (1..10).map { |i| ["a#{i}", {data_type: "String", string_value: "v"}] }.to_h
      sqs.send_message(queue_url: queue_url, message_body: "hi", message_attributes: attributes)

      expect(sent_params(sqs, :send_message)[:message_attributes].keys).not_to include("_datadog")
    end

    it "does not modify the caller's params" do
      params = {queue_url: queue_url, message_body: "hi", message_attributes: {}}.freeze
      sqs.send_message(params)

      expect(params[:message_attributes]).to be_empty
    end

    context "when Data Streams is disabled" do
      let(:data_streams_enabled) { false }

      it "adds no attribute" do
        sqs.send_message(queue_url: queue_url, message_body: "hi")

        expect(sent_params(sqs, :send_message)[:message_attributes]).to be_nil
      end
    end
  end

  describe "SQS send_message_batch" do
    it "writes the pathway into every entry" do
      sqs.send_message_batch(
        queue_url: queue_url,
        entries: [{id: "1", message_body: "a"}, {id: "2", message_body: "b"}],
      )

      entries = sent_params(sqs, :send_message_batch)[:entries]
      expect(entries.map { |e| e[:message_attributes]["_datadog"][:data_type] }).to eq(["String", "String"])
    end
  end

  describe "SQS receive_message" do
    it "requests the _datadog attribute" do
      sqs.receive_message(queue_url: queue_url, message_attribute_names: ["tenant"])

      expect(sent_params(sqs, :receive_message)[:message_attribute_names]).to eq(["tenant", "_datadog"])
    end

    it "keeps a request for all attributes as is" do
      sqs.receive_message(queue_url: queue_url, message_attribute_names: ["All"])

      expect(sent_params(sqs, :receive_message)[:message_attribute_names]).to eq(["All"])
    end

    it "continues the pathway written by the producer" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")
      carrier = sent_params(sqs, :send_message)[:message_attributes]["_datadog"][:string_value]
      Datadog::DataStreams.pathway_context = nil

      context = consume_messages([{message_id: "1", body: "hi", message_attributes: {"_datadog" => {data_type: "String", string_value: carrier}}}])

      expect(context.parent_hash).to eq(produced_hash(pathway_from(carrier)))
    end

    it "reads .NET's double base64 encoded pathway" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")
      encoded = pathway_from(sent_params(sqs, :send_message)[:message_attributes]["_datadog"][:string_value])
      double = JSON.generate("dd-pathway-ctx-base64" => Datadog::Core::Utils::Base64Codec.strict_encode64(encoded))
      Datadog::DataStreams.pathway_context = nil

      context = consume_messages([{message_id: "1", body: "hi", message_attributes: {"_datadog" => {data_type: "String", string_value: double}}}])

      expect(context.parent_hash).to eq(produced_hash(encoded))
    end

    it "starts a new pathway for a message without context" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")

      context = consume_messages([{message_id: "1", body: "plain"}])

      expect(context.parent_hash).to eq(0)
    end

    it "restores the caller's context after consuming a batch" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")
      carrier = sent_params(sqs, :send_message)[:message_attributes]["_datadog"][:string_value]
      caller_context = Datadog::DataStreams.pathway_context
      attribute = {data_type: "String", string_value: carrier}

      context = consume_messages([
        {message_id: "1", body: "a", message_attributes: {"_datadog" => attribute}},
        {message_id: "2", body: "b", message_attributes: {"_datadog" => attribute}},
      ])

      expect(context).to equal(caller_context)
    end

    it "keeps consuming when an earlier message in the batch is malformed" do
      sqs.send_message(queue_url: queue_url, message_body: "hi")
      carrier = sent_params(sqs, :send_message)[:message_attributes]["_datadog"][:string_value]
      Datadog::DataStreams.pathway_context = nil
      malformed = JSON.generate("Type" => "Notification", "MessageAttributes" => "not-a-hash")

      consume_messages([
        {message_id: "1", body: malformed},
        {message_id: "2", body: "hi", message_attributes: {"_datadog" => {data_type: "String", string_value: carrier}}},
      ])

      expect(spans.last.get_tag("pathway.hash")).to match(/\A\d+\z/)
    end
  end

  describe "SNS" do
    def published_carrier
      attribute = sent_params(sns, :publish)[:message_attributes]["_datadog"]
      expect(attribute[:data_type]).to eq("Binary")
      attribute[:binary_value]
    end

    it "writes the pathway into a Binary _datadog attribute on publish" do
      sns.publish(topic_arn: topic_arn, message: "hi")

      expect(produced_hash(pathway_from(published_carrier))).to be > 0
    end

    it "writes the pathway into every publish_batch entry" do
      sns.publish_batch(
        topic_arn: topic_arn,
        publish_batch_request_entries: [{id: "1", message: "a"}, {id: "2", message: "b"}],
      )

      entries = sent_params(sns, :publish_batch)[:publish_batch_request_entries]
      expect(entries.map { |e| e[:message_attributes]["_datadog"][:data_type] }).to eq(["Binary", "Binary"])
    end

    it "continues the pathway through an SQS subscription's notification body" do
      sns.publish(topic_arn: topic_arn, message: "hi")
      carrier = published_carrier
      Datadog::DataStreams.pathway_context = nil
      body = JSON.generate(
        "Type" => "Notification",
        "Message" => "hi",
        "MessageAttributes" => {
          "_datadog" => {"Type" => "Binary", "Value" => Datadog::Core::Utils::Base64Codec.strict_encode64(carrier)},
        },
      )

      context = consume_messages([{message_id: "1", body: body}])

      expect(context.parent_hash).to eq(produced_hash(pathway_from(carrier)))
    end

    it "continues the pathway through raw message delivery" do
      sns.publish(topic_arn: topic_arn, message: "hi")
      carrier = published_carrier
      Datadog::DataStreams.pathway_context = nil

      context = consume_messages([{message_id: "1", body: "hi", message_attributes: {"_datadog" => {data_type: "Binary", binary_value: carrier}}}])

      expect(context.parent_hash).to eq(produced_hash(pathway_from(carrier)))
    end
  end
end
