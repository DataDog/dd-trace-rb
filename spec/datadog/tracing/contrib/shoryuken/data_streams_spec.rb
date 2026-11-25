# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "aws-sdk"
require "shoryuken"

require "datadog"

RSpec.describe "Shoryuken Data Streams context" do
  let(:queue_url) { "https://sqs.us-east-1.amazonaws.com/123456789012/orders" }
  let(:downstream_url) { "https://sqs.us-east-1.amazonaws.com/123456789012/shipments" }
  let(:sqs) { Aws::SQS::Client.new(stub_responses: true) }
  let(:shoryuken_queue) { instance_double(Shoryuken::Queue, url: queue_url, name: "orders") }

  before do
    skip_if_libdatadog_not_supported

    Datadog.configure do |c|
      c.tracing.instrument :aws
      c.tracing.instrument :shoryuken
      c.data_streams.enabled = true
    end
    Datadog::DataStreams.pathway_context = nil
  end

  around do |example|
    Datadog.registry[:aws].reset_configuration!
    Datadog.registry[:shoryuken].reset_configuration!
    example.run
    Datadog.registry[:aws].reset_configuration!
    Datadog.registry[:shoryuken].reset_configuration!
  end

  def sent_params(operation)
    sqs.api_requests.reverse.find { |r| r[:operation_name] == operation }[:params]
  end

  it "parents the worker's produce checkpoint on the consume checkpoint from another thread" do
    sqs.send_message(queue_url: queue_url, message_body: "hi")
    upstream = sent_params(:send_message)[:message_attributes]["_datadog"]
    Datadog::DataStreams.pathway_context = nil

    sqs.stub_responses(
      :receive_message,
      messages: [{message_id: "1", body: "hi", message_attributes: {"_datadog" => upstream}}],
    )
    received = sqs.receive_message(queue_url: queue_url).messages.first
    consume_hash = Datadog::DataStreams.pathway_context.hash
    sqs_msg = Shoryuken::Message.new(sqs, shoryuken_queue, received)

    produce_parent = Thread.new do
      Datadog::Tracing::Contrib::Shoryuken::Tracer.new.call(double("worker"), "orders", sqs_msg, "hi") do
        sqs.send_message(queue_url: downstream_url, message_body: "next")
        Datadog::DataStreams.pathway_context.parent_hash
      end
    end.value

    expect(produce_parent).to eq(consume_hash)
  end

  it "restores the worker thread's context after processing" do
    sqs.stub_responses(:receive_message, messages: [{message_id: "1", body: "hi"}])
    received = sqs.receive_message(queue_url: queue_url).messages.first
    sqs_msg = Shoryuken::Message.new(sqs, shoryuken_queue, received)

    context_after = Thread.new do
      Datadog::Tracing::Contrib::Shoryuken::Tracer.new.call(double("worker"), "orders", sqs_msg, "hi") {}
      Datadog::DataStreams.pathway_context
    end.value

    expect(context_after).to be_nil
  end

  it "does not restore the saved context into a replaced processor" do
    sqs.stub_responses(:receive_message, messages: [{message_id: "1", body: "hi"}])
    received = sqs.receive_message(queue_url: queue_url).messages.first
    sqs_msg = Shoryuken::Message.new(sqs, shoryuken_queue, received)
    replacement = instance_double(Datadog::DataStreams::Processor)
    expect(replacement).not_to receive(:pathway_context=)

    Datadog::Tracing::Contrib::Shoryuken::Tracer.new.call(double("worker"), "orders", sqs_msg, "hi") do
      allow(Datadog::DataStreams).to receive(:processor).and_return(replacement)
    end
  end
end
