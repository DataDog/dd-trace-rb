require 'spec_helper'

require 'datadog/profiling/old_recorder'
require 'datadog/profiling/event'

RSpec.describe Datadog::Profiling::OldRecorder do
  subject(:recorder) do
    described_class.new(event_classes, max_size, **options)
  end

  let(:event_classes) { [] }
  let(:max_size) { 0 }
  let(:options) { {} }

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

  describe '#serialize' do
    include_context 'test buffer'

    let(:events) { [] }
    let(:event_classes) { [event_class] }
    let(:event_class) { Class.new(Datadog::Profiling::Event) }

    subject(:serialize) { recorder.serialize }

    before { allow(buffer).to receive(:pop).and_return(events) }

    context 'whose buffer returns events' do
      let(:events) { [event_class.new, event_class.new] }
      let(:pprof_data) { 'dummy encoded pprof data' }

      before do
        allow(Datadog::Profiling::Encoding::Profile::Protobuf).to receive(:encode).and_return(pprof_data)
      end

      it 'returns a tuple with the profiling data' do
        start, finish, pprof_data = serialize

        expect(start).to be_a_kind_of(Time)
        expect(finish).to be_a_kind_of(Time)
        expect(pprof_data).to be pprof_data
      end

      it 'calls the protobuf encoder with the events' do
        expected_event_group = instance_double(Datadog::Profiling::EventGroup)

        expect(Datadog::Profiling::EventGroup)
          .to receive(:new).with(event_class, events).and_return(expected_event_group)
        expect(Datadog::Profiling::Encoding::Profile::Protobuf).to receive(:encode).with(
          start: kind_of(Time),
          finish: kind_of(Time),
          event_groups: [expected_event_group],
          event_count: 2,
        )

        serialize
      end

      context 'called back to back' do
        subject(:flush) do
          Array.new(3) do
            start, finish = recorder.serialize
            OpenStruct.new(start: start, finish: finish)
          end
        end

        it 'has its start and end times line up' do
          expect(flush[0].start).to be < flush[0].finish
          expect(flush[0].finish).to eq flush[1].start
          expect(flush[1].finish).to eq flush[2].start
          expect(flush[2].start).to be < flush[2].finish
        end
      end
    end

    context 'whose buffer returns no events' do
      it { is_expected.to be nil }
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { recorder.reset_after_fork }

    before do
      allow(Datadog.logger).to receive(:debug)
    end

    it { is_expected.to be nil }

    it 'debug logs the reset event' do
      expect(Datadog.logger).to receive(:debug).with(/Resetting/)

      reset_after_fork
    end

    # NOTE: This again is a bit of a heavy-handed way of testing this method, but we plan to remove it soon anyway
    it 'triggers a serialize call' do
      expect(recorder).to receive(:serialize)

      reset_after_fork
    end
  end
end
