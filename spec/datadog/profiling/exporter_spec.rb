# typed: false

require 'datadog/profiling/exporter'
require 'datadog/profiling/old_recorder'
require 'datadog/profiling/collectors/code_provenance'
require 'datadog/core/logger'

RSpec.describe Datadog::Profiling::Exporter do
  subject(:exporter) do
    described_class.new(pprof_recorder: pprof_recorder, code_provenance_collector: code_provenance_collector, **options)
  end

  let(:start) { Time.now }
  let(:finish) { start + 60 }
  let(:pprof_data) { 'dummy pprof data' }
  let(:code_provenance_data) { 'dummy code provenance data' }
  let(:pprof_recorder_serialize) { [start, finish, pprof_data] }
  let(:pprof_recorder) { instance_double(Datadog::Profiling::OldRecorder, serialize: pprof_recorder_serialize) }
  let(:code_provenance_collector) do
    collector = instance_double(Datadog::Profiling::Collectors::CodeProvenance, generate_json: code_provenance_data)
    allow(collector).to receive(:refresh).and_return(collector)
    collector
  end
  let(:logger) { Datadog.logger }
  let(:options) { {} }

  describe '#flush' do
    subject(:flush) { exporter.flush }

    it 'returns a flush containing the data from the recorders' do
      expect(flush).to have_attributes(
        start: start,
        finish: finish,
        pprof_file_name: 'rubyprofile.pprof',
        code_provenance_file_name: 'code-provenance.json',
        tags_as_array: array_including(%w[language ruby], ['process_id', Process.pid.to_s]),
      )
      expect(flush.pprof_data).to eq pprof_data
      expect(flush.code_provenance_data).to eq code_provenance_data
    end

    context 'when pprof recorder has no data' do
      let(:pprof_recorder_serialize) { nil }

      it { is_expected.to be nil }
    end

    context 'when no code provenance collector was provided' do
      let(:code_provenance_collector) { nil }

      it 'returns a flush with nil code_provenance_data' do
        expect(flush.code_provenance_data).to be nil
      end
    end

    context 'when duration of profile is below 1s' do
      let(:finish) { start + 0.99 }

      before { allow(logger).to receive(:debug) }

      it { is_expected.to be nil }

      it 'logs a debug message' do
        expect(logger).to receive(:debug).with(/Skipped exporting/)

        flush
      end
    end

    context 'when duration of profile is 1s or above' do
      let(:finish) { start + 1 }

      it { is_expected.to_not be nil }
    end
  end

  describe '#clear' do
    subject(:clear) { exporter.clear }

    it { is_expected.to be nil }

    context 'when pprof_recorder does not support clear' do
      let(:pprof_recorder) { instance_double(Datadog::Profiling::OldRecorder, serialize: pprof_recorder_serialize) }

      it 'triggers pprof_recorder serialization' do
        expect(pprof_recorder).to receive(:serialize)

        clear
      end

      it 'sets the last_flush_finish_at to the result of serialize' do
        clear

        expect(exporter.send(:last_flush_finish_at)).to be finish
      end
    end

    context 'when pprof_recorder supports clear' do
      let(:pprof_recorder) { instance_double(Datadog::Profiling::StackRecorder, clear: finish) }

      it 'triggers pprof_recorder clear' do
        expect(pprof_recorder).to receive(:clear)

        clear
      end

      it 'sets the last_flush_finish_at to the result of clear' do
        clear

        expect(exporter.send(:last_flush_finish_at)).to be finish
      end
    end
  end

  describe '#can_flush?' do
    let(:time_provider) { class_double(Time) }
    let(:created_at) { start - 60 }
    let(:options) { { **super(), time_provider: time_provider } }

    subject(:can_flush?) { exporter.can_flush? }

    before do
      expect(time_provider).to receive(:now).and_return(created_at).once
      exporter
    end

    context 'when exporter has flushed before' do
      before { exporter.flush }

      context 'when less than 1s has elapsed since last flush' do
        before { expect(time_provider).to receive(:now).and_return(finish + 0.99).once }

        it { is_expected.to be false }
      end

      context 'when 1s or more has elapsed since last flush' do
        before { expect(time_provider).to receive(:now).and_return(finish + 1).once }

        it { is_expected.to be true }
      end
    end

    context 'when exporter has been cleared before' do
      before { exporter.clear }

      context 'when less than 1s has elapsed since last clear' do
        before { expect(time_provider).to receive(:now).and_return(finish + 0.99).once }

        it { is_expected.to be false }
      end

      context 'when 1s or more has elapsed since last clear' do
        before { expect(time_provider).to receive(:now).and_return(finish + 1).once }

        it { is_expected.to be true }
      end
    end

    context 'when exporter has never flushed or cleared' do
      context 'when less than 1s has elapsed since exporter was created' do
        before { expect(time_provider).to receive(:now).and_return(created_at + 0.99).once }

        it { is_expected.to be false }
      end

      context 'when 1s or more has elapsed since exporter was created' do
        before { expect(time_provider).to receive(:now).and_return(created_at + 1).once }

        it { is_expected.to be true }
      end
    end
  end
end
