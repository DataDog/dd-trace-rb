require 'spec_helper'

require 'datadog/core/telemetry/event/message_batch'

RSpec.describe Datadog::Core::Telemetry::Event::MessageBatch do
  let(:id) { double('seq_id') }
  let(:event) { event_class.new }

  subject(:payload) { event.payload }

  let(:event_class) { described_class }
  let(:event) { event_class.new(events) }

  let(:events) do
    [
      Datadog::Core::Telemetry::Event::AppClosing.new,
      Datadog::Core::Telemetry::Event::AppHeartbeat.new,
    ]
  end

  it do
    is_expected.to eq(
      [
        {
          request_type: 'app-closing',
          payload: {}
        },
        {
          request_type: 'app-heartbeat',
          payload: {}
        }
      ]
    )
  end
end
