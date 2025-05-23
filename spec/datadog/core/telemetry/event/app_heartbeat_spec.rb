require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::AppHeartbeat do
  let(:id) { double('seq_id') }
  let(:event) { event_class.new }

  subject(:payload) { event.payload }

  let(:event_class) { described_class }
  it_behaves_like 'telemetry event with no attributes'

  it 'has no payload' do
    is_expected.to eq({})
  end
end
