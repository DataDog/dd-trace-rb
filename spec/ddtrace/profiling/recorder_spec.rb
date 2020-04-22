require 'spec_helper'

require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/event'

RSpec.describe Datadog::Profiling::Recorder do
  subject(:recorder) { described_class.new(event_classes, max_size) }
  let(:event_classes) { [] }
  let(:max_size) { 0 }

  shared_context 'test buffer' do
    let(:buffer) { instance_double(Datadog::Profiling::Buffer) }

    before do
      allow(Datadog::Profiling::Buffer)
        .to receive(:new)
        .with(max_size)
        .and_return(buffer)
    end
  end

  describe '::new' do
    context 'given events of different classes' do
      let(:event_classes) { [event_one.class, event_two.class] }
      let(:event_one) { Class.new(Datadog::Profiling::Event).new }
      let(:event_two) { Class.new(Datadog::Profiling::Event).new }

      it 'creates a buffer per class' do
        expect(Datadog::Profiling::Buffer)
          .to receive(:new)
          .with(max_size)
          .twice

        recorder
      end
    end
  end

  describe '#push' do
    include_context 'test buffer'
    subject(:push) { recorder.push(event) }

    before { allow(buffer).to receive(:push) }

    context 'given an event' do
      let(:event) { event_class.new }
      let(:event_class) { Class.new(Datadog::Profiling::Event) }

      context 'whose class has not been registered' do
        it do
          expect { push }.to raise_error(described_class::UnknownEventError)
        end
      end

      context 'whose class has been registered' do
        let(:event_classes) { [event_class] }

        it do
          push
          expect(buffer).to have_received(:push).with(event)
        end
      end
    end
  end

  describe '#pop' do
    include_context 'test buffer'
    subject(:pop) { recorder.pop(event_class) }

    before { allow(buffer).to receive(:pop) }

    context 'given an event class' do
      let(:event_class) { Class.new(Datadog::Profiling::Event) }

      context 'when event class has not been registered' do
        it do
          expect { pop }.to raise_error(described_class::UnknownEventError)
        end
      end

      context 'when a matching event has been pushed' do
        let(:event_classes) { [event_class] }

        it do
          pop
          expect(buffer).to have_received(:pop)
        end
      end
    end
  end
end
