# typed: false
require 'spec_helper'

require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/event'
require 'ddtrace/profiling/collectors/code_provenance'

RSpec.describe Datadog::Profiling::Recorder do
  subject(:recorder) do
    described_class.new(event_classes, max_size, code_provenance_collector: code_provenance_collector)
  end

  let(:event_classes) { [] }
  let(:max_size) { 0 }
  let(:code_provenance_collector) { nil }

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

  describe '#[]' do
    subject(:buffer) { recorder[event_class] }

    context 'given an event class that is defined' do
      let(:event_class) { Class.new }
      let(:event_classes) { [event_class] }

      it { is_expected.to be_a_kind_of(Datadog::Profiling::Buffer) }
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

    let(:events) { [] }

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
        it { is_expected.to be_a_kind_of(Datadog::Profiling::Flush) }
        it { expect(flush.event_groups).to be_empty }
      end

      context 'called back to back' do
        subject(:flush) { Array.new(3) { recorder.flush } }

        it 'has its start and end times line up' do
          expect(flush[0].start).to be < flush[0].finish
          expect(flush[0].finish).to eq(flush[1].start)
          expect(flush[1].finish).to eq(flush[2].start)
          expect(flush[2].start).to be < flush[2].finish
        end
      end
    end

    context 'when code_provenance_collector is nil' do
      let(:code_provenance_collector) { nil }

      it 'returns a flush without code_provenance' do
        expect(flush.code_provenance).to be nil
      end
    end

    context 'when code_provenance_collector is available' do
      let(:code_provenance_collector) do
        collector = instance_double(Datadog::Profiling::Collectors::CodeProvenance, generate_json: code_provenance)
        allow(collector).to receive(:refresh).and_return(collector)
        collector
      end
      let(:code_provenance) { double('code_provenance') } # rubocop:disable RSpec/VerifiedDoubles

      it 'returns a flush with code_provenance' do
        expect(flush.code_provenance).to be code_provenance
      end
    end
  end

  describe '#empty?' do
    let(:event_classes) { [event_class] }
    let(:event_class) { Class.new(Datadog::Profiling::Event) }

    context 'when there are no events recorded' do
      it { is_expected.to be_empty }
    end

    context 'when there are recorded events' do
      before do
        recorder.push(event_class.new)
      end

      it { is_expected.to_not be_empty }
    end
  end
end
