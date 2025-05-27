require 'spec_helper'

require 'datadog/core/telemetry/event/app_client_configuration_change'

RSpec.describe Datadog::Core::Telemetry::Event::AppClientConfigurationChange do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  subject(:payload) { event.payload }

  let(:event) { described_class.new(changes, origin) }
  let(:changes) { { name => value } }
  let(:origin) { double('origin') }
  let(:name) { 'key' }
  let(:value) { 'value' }

  before do
    allow_any_instance_of(Datadog::Core::Utils::Sequence).to receive(:next).and_return(id)
  end

  it 'has a list of client configurations' do
    is_expected.to eq(
      configuration: [{
        name: name,
        value: value,
        origin: origin,
        seq_id: id
      }]
    )
  end

  context 'with env_var state configuration' do
    before do
      Datadog.configure do |c|
        c.appsec.sca_enabled = false
      end
    end

    it 'includes sca enablement configuration' do
      is_expected.to eq(
        configuration:
        [
          { name: name, value: value, origin: origin, seq_id: id },
          { name: 'appsec.sca_enabled', value: false, origin: 'code', seq_id: id }
        ]
      )
    end
  end

  it 'all events to be the same' do
    events =     [
      described_class.new({ 'key' => 'value' }, 'origin'),
      described_class.new({ 'key' => 'value' }, 'origin'),
    ]

    expect(events.uniq).to have(1).item
  end

  it 'all events to be different' do
    events =     [
      described_class.new({ 'key' => 'value' }, 'origin'),
      described_class.new({ 'key' => 'value' }, 'origin2'),
      described_class.new({ 'key' => 'value2' }, 'origin'),
      described_class.new({ 'key2' => 'value' }, 'origin'),
      described_class.new({}, 'origin'),
    ]

    expect(events.uniq).to eq(events)
  end
end
