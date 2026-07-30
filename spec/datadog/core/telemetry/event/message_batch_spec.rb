require "spec_helper"

require "datadog/core/telemetry/event/message_batch"

RSpec.describe Datadog::Core::Telemetry::Event::MessageBatch do
  let(:id) { double("seq_id") }
  let(:event) { described_class.new }

  let(:event) { described_class.new(events) }

  let(:events) do
    [
      Datadog::Core::Telemetry::Event::AppClosing.new,
      Datadog::Core::Telemetry::Event::AppHeartbeat.new,
    ]
  end

  describe ".payload" do
    subject(:payload) { event.payload }

    it do
      is_expected.to eq(
        [
          {
            request_type: "app-closing",
            payload: {}
          },
          {
            request_type: "app-heartbeat",
            payload: {}
          }
        ]
      )
    end

    context "with an app-client-configuration-change event" do
      let(:events) do
        [
          Datadog::Core::Telemetry::Event::AppClientConfigurationChange.new(
            [["DD_TRACE_HEADER_TAGS", ["X-Test-Header:test_header_rc", "Content-Length:"]]],
            "remote_config"
          )
        ]
      end

      it "contains a scalar configuration value" do
        is_expected.to eq(
          [
            {
              request_type: "app-client-configuration-change",
              payload: {
                configuration: [
                  {
                    name: "DD_TRACE_HEADER_TAGS",
                    value: "X-Test-Header:test_header_rc,Content-Length:",
                    origin: "remote_config",
                    seq_id: 6,
                  }
                ]
              }
            }
          ]
        )
      end
    end

    context "with a floating-point app-client-configuration-change value" do
      let(:events) do
        [
          Datadog::Core::Telemetry::Event::AppClientConfigurationChange.new(
            [["DD_TRACE_SAMPLE_RATE", 0.2]],
            "remote_config"
          )
        ]
      end

      it "preserves the numeric value" do
        is_expected.to eq(
          [
            {
              request_type: "app-client-configuration-change",
              payload: {
                configuration: [
                  {
                    name: "DD_TRACE_SAMPLE_RATE",
                    value: 0.2,
                    origin: "remote_config",
                    seq_id: 6,
                  }
                ]
              }
            }
          ]
        )
      end
    end
  end
end
