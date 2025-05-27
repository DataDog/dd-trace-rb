require 'spec_helper'

require 'datadog/core/telemetry/event/log'

RSpec.describe Datadog::Core::Telemetry::Event::Log do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  subject(:payload) { event.payload }

  it do
    event = Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :error)
    expect(event.type).to eq('logs')
    expect(event.payload).to eq(
      {
        logs: [{
          message: 'Hi',
          level: 'ERROR',
          count: 1
        }]
      }
    )
  end

  it do
    event = Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :warn)
    expect(event.type).to eq('logs')
    expect(event.payload).to eq(
      {
        logs: [{
          message: 'Hi',
          level: 'WARN',
          count: 1
        }]
      }
    )
  end

  it do
    expect do
      Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :unknown)
    end.to raise_error(ArgumentError, /Invalid log level/)
  end

  it 'all events to be the same' do
    events =     [
      described_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
      described_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
    ]

    expect(events.uniq).to have(1).item
  end

  it 'all events to be different' do
    events =     [
      described_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
      described_class.new(message: 'Yo', level: :warn, stack_trace: 'stack trace', count: 1),
      described_class.new(message: 'Hi', level: :error, stack_trace: 'stack trace', count: 1),
      described_class.new(message: 'Hi', level: :warn, stack_trace: 'stack&trace', count: 1),
      described_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 2),
    ]

    expect(events.uniq).to eq(events)
  end
end
