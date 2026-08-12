# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "waterdrop"
require "datadog"

RSpec.describe "WaterDrop middleware" do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :waterdrop, tracing_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:waterdrop].reset_configuration!
    example.run
    Datadog.registry[:waterdrop].reset_configuration!
  end

  subject(:middleware) { Datadog::Tracing::Contrib::WaterDrop::Middleware }

  let(:producer) do
    WaterDrop::Producer.new do |config|
      # Dummy - doesn't try to connect to Kafka
      config.client_class = WaterDrop::Clients::Buffered
    end
  end

  let(:tracing_options) { {distributed_tracing: false} }

  describe ".instrument" do
    context "when distributed tracing is disabled" do
      it "does not propagate trace context in message headers" do
        message_1 = {topic: "topic_name", payload: "foo"}
        Datadog::Tracing.trace("test.span") do
          middleware.call(message_1)
        end

        expect(message_1[:headers]).to be_nil
      end
    end

    context "when distributed tracing is enabled" do
      let(:tracing_options) { {distributed_tracing: true} }

      it "propagates trace context in message headers" do
        message = {topic: "topic_name", payload: "foo"}
        Datadog::Tracing.trace("test.span") do
          middleware.call(message)
        end

        expect(message[:headers]).to include(
          "x-datadog-trace-id" => low_order_trace_id(span.trace_id).to_s,
          "x-datadog-parent-id" => span.id.to_s
        )
      end
    end

    context "when DataStreams is enabled" do
      before do
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(true)
        allow(Datadog::DataStreams).to receive(:set_produce_checkpoint) do |**_kwargs, &block|
          block.call("data_streams_key", "data_streams_value")
        end
      end

      it "calls set_produce_checkpoint and injects headers" do
        message = {topic: "some_topic", payload: "hello"}

        middleware.call(message)

        expect(Datadog::DataStreams).to have_received(:set_produce_checkpoint).with(
          type: "kafka",
          destination: "some_topic",
          auto_instrumentation: true
        )
        expect(message[:headers]).to include("data_streams_key" => "data_streams_value")
      end

      it "initializes headers if not present" do
        message = {topic: "some_topic", payload: "hello"}

        middleware.call(message)

        expect(Datadog::DataStreams).to have_received(:set_produce_checkpoint).with(
          type: "kafka",
          destination: "some_topic",
          auto_instrumentation: true
        )
      end

      it "preserves existing headers" do
        message = {topic: "some_topic", payload: "hello", headers: {"existing" => "header"}}

        middleware.call(message)

        expect(message[:headers]).to include(
          "data_streams_key" => "data_streams_value",
          "existing" => "header"
        )
      end

      it "does not raise for frozen existing headers" do
        source_headers = {"existing" => "header", "binary" => "\x00\xFF".b}.freeze
        message = {topic: "some_topic", payload: "hello", headers: source_headers}

        expect { middleware.call(message) }.not_to raise_error
      end

      it "leaves the frozen source headers unchanged" do
        source_headers = {"existing" => "header", "binary" => "\x00\xFF".b}.freeze
        message = {topic: "some_topic", payload: "hello", headers: source_headers}

        middleware.call(message)

        expect(source_headers).to eq("existing" => "header", "binary" => "\x00\xFF".b)
      end

      it "keeps the source headers frozen" do
        source_headers = {"existing" => "header", "binary" => "\x00\xFF".b}.freeze
        message = {topic: "some_topic", payload: "hello", headers: source_headers}

        middleware.call(message)

        expect(source_headers).to be_frozen
      end

      it "copies the source headers before injecting the pathway context" do
        source_headers = {"existing" => "header", "binary" => "\x00\xFF".b}.freeze
        message = {topic: "some_topic", payload: "hello", headers: source_headers}

        middleware.call(message)

        expect(message[:headers]).not_to equal(source_headers)
      end

      it "preserves existing and binary headers while injecting the pathway context" do
        source_headers = {"existing" => "header", "binary" => "\x00\xFF".b}.freeze
        message = {topic: "some_topic", payload: "hello", headers: source_headers}

        middleware.call(message)

        expect(message[:headers]).to eq(
          "existing" => "header",
          "binary" => "\x00\xFF".b,
          "data_streams_key" => "data_streams_value"
        )
      end
    end

    context "when DataStreams is disabled" do
      before do
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(false)
        allow(Datadog::DataStreams).to receive(:set_produce_checkpoint)
      end

      it "does not call set_produce_checkpoint" do
        message = {topic: "some_topic", payload: "hello"}

        middleware.call(message)

        expect(Datadog::DataStreams).not_to have_received(:set_produce_checkpoint)
      end
    end
  end
end
