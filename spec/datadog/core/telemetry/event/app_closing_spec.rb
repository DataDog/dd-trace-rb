require 'spec_helper'

require 'datadog/core/telemetry/event/app_closing'

RSpec.describe Datadog::Core::Telemetry::Event::AppClosing do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  it_behaves_like 'telemetry event with no attributes'

  describe '.payload' do
    subject(:payload) { event.payload }

    it 'is empty' do
      is_expected.to eq({})
    end
  end
end
