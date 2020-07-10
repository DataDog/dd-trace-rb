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
    it do
      is_expected.to have_attributes(
        max_size: max_size
      )
    end

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

    let(:event_class) { Class.new(Datadog::Profiling::Event) }

    before do
      allow(buffer).to receive(:push)
      allow(buffer).to receive(:concat)
    end

    context 'given an event' do
      subject(:push) { recorder.push(event) }
      let(:event) { event_class.new }

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

    context 'given an Array of events' do
      subject(:push) { recorder.push(events) }
      let(:events) { Array.new(2) { event_class.new } }

      context 'whose class has not been registered' do
        it do
          expect { push }.to raise_error(described_class::UnknownEventError)
        end
      end

      context 'whose class has been registered' do
        let(:event_classes) { [event_class] }

        it do
          push
          expect(buffer).to have_received(:concat).with(events)
        end
      end
    end
  end

  describe '#flush' do
    include_context 'test buffer'
    subject(:flush) { recorder.flush }

    before { allow(buffer).to receive(:pop).and_return(events) }

    context 'when the Recorder has a registered event class' do
      let(:event_classes) { [event_class] }
      let(:event_class) { Class.new(Datadog::Profiling::Event) }

      context 'whose buffer returns events' do
        let(:events) { [event_class.new, event_class.new] }

        it { is_expected.to be_a_kind_of(Datadog::Profiling::Flush) }

        it do
          is_expected.to have_attributes(
            start: kind_of(Time),
            finish: kind_of(Time),
            event_groups: array_including(Datadog::Profiling::EventGroup),
            event_count: 2
          )
        end

        it { expect(flush.event_groups).to be_a_kind_of(Array) }
        it { expect(flush.event_groups).to have(1).item }
        it { expect(flush.start).to be < flush.finish }

        it 'produces a flush with the events' do
          expect(flush.event_groups.first).to have_attributes(
            event_class: event_class,
            events: events
          )
        end
      end

      context 'whose buffer returns no events' do
        let(:events) { [] }
        it { is_expected.to be_a_kind_of(Datadog::Profiling::Flush) }
        it { expect(flush.event_groups).to be_empty }
      end

      context 'called back to back' do
        subject(:flush) { Array.new(3) { recorder.flush } }
        let(:events) { [] }

        it 'has its start and end times line up' do
          expect(flush[0].start).to be < flush[0].finish
          expect(flush[0].finish).to eq(flush[1].start)
          expect(flush[1].finish).to eq(flush[2].start)
          expect(flush[2].start).to be < flush[2].finish
        end
      end
    end
  end
end
