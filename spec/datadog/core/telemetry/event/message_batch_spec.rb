require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::MessageBatch do
  let(:id) { double('seq_id') }
  let(:event) { event_class.new }

  subject(:payload) { event.payload }

  let(:event_class) { described_class }
  let(:event) { event_class.new(events) }

  let(:events) { [described_class::AppClosing.new, described_class::AppHeartbeat.new] }

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
