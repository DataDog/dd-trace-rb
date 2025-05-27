require 'spec_helper'

require 'datadog/core/telemetry/event/app_heartbeat'

RSpec.describe Datadog::Core::Telemetry::Event::AppHeartbeat do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  subject(:payload) { event.payload }

  it_behaves_like 'telemetry event with no attributes'

  it 'has no payload' do
    is_expected.to eq({})
  end
end
