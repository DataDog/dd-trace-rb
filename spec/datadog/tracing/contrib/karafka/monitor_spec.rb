# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"

require "karafka"
require "datadog"

RSpec.describe "Karafka monitor" do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :karafka, {distributed_tracing: true}
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:karafka].reset_configuration!
    example.run
    Datadog.registry[:karafka].reset_configuration!
  end

  describe ".instrument" do
    context "when the event is not traceable" do
      it "does not create a trace" do
        Karafka.monitor.instrument("worker.completed")

        # NOTE: This helper doesn't workt with `change` matcher well.
        expect(traces).to have(0).items
        expect(spans).to have(0).items
      end
    end

    context "when the event is traceable" do
      let(:consume_job_class) do
        if defined?(Karafka::Processing::ConsumerGroups::Jobs::Consume) # Karafka 2.6
          Karafka::Processing::ConsumerGroups::Jobs::Consume
        else
          Karafka::Processing::Jobs::Consume
        end
      end
      let(:executor_class) do
        if defined?(Karafka::Processing::ConsumerGroups::Executor) # Karafka 2.6
          Karafka::Processing::ConsumerGroups::Executor
        else
          Karafka::Processing::Executor
        end
      end
      let(:job) do
        instance_double(consume_job_class, class: consume_job_class, executor: executor, messages: messages)
      end
      let(:executor) { instance_double(executor_class, topic: topic, partition: 1) }
      let(:topic) do
        instance_double(Karafka::Routing::Topic, consumer: "Consumer", name: "topic_name", kafka: kafka_config)
      end
      let(:kafka_config) { {"bootstrap.servers": "kafka-1:9092,kafka-2:9092"} }
      let(:messages) { [instance_double(Karafka::Messages::Messages, metadata: metadata)] }
      let(:metadata) { instance_double(Karafka::Messages::Metadata, offset: 42) }

      it "traces a consumer job" do
        Karafka.monitor.instrument("worker.processed", {job: job})

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq("Consumer#consume")
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => 1,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_OFFSET => 42,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_CONSUMER => "Consumer",
          "messaging.destination" => "topic_name",
          "messaging.system" => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
          "span.kind" => "consumer",
          "messaging.kafka.bootstrap.servers" => "kafka-1:9092,kafka-2:9092",
        )
      end

      context "when the topic has no bootstrap.servers configured" do
        let(:kafka_config) { {} }

        it "does not set the bootstrap servers tag" do
          Karafka.monitor.instrument("worker.processed", {job: job})

          expect(spans[0].get_tag("messaging.kafka.bootstrap.servers")).to be_nil
        end
      end
    end
  end
end
