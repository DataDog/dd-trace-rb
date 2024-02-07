require 'datadog/profiling/spec_helper'

require 'datadog/profiling/exporter'
require 'datadog/profiling/collectors/code_provenance'
require 'datadog/core/logger'

RSpec.describe Datadog::Profiling::Exporter do
  before { skip_if_profiling_not_supported(self) }

  subject(:exporter) do
    described_class.new(
      pprof_recorder: pprof_recorder,
      worker: worker,
      code_provenance_collector: code_provenance_collector,
      internal_metadata: internal_metadata,
      **options
    )
  end

  let(:start) { Time.now }
  let(:finish) { start + 60 }
  let(:pprof_data) { 'dummy pprof data' }
  let(:code_provenance_data) { 'dummy code provenance data' }
  let(:pprof_recorder_serialize) { [start, finish, pprof_data] }
  let(:pprof_recorder) { instance_double(Datadog::Profiling::StackRecorder, serialize: pprof_recorder_serialize) }
  let(:worker) do
    # TODO: Change this to a direct reference when we drop support for old Rubies which currently error if we try
    #       to `require 'profiling/collectors/cpu_and_wall_time_worker'`
    instance_double('Datadog::Profiling::Collectors::CpuAndWallTimeWorker', stats_and_reset_not_thread_safe: stats)
  end
  let(:code_provenance_collector) do
    collector = instance_double(Datadog::Profiling::Collectors::CodeProvenance, generate_json: code_provenance_data)
    allow(collector).to receive(:refresh).and_return(collector)
    collector
  end
  let(:internal_metadata) { { no_signals_workaround_enabled: no_signals_workaround_enabled } }
  let(:no_signals_workaround_enabled) { false }
  let(:logger) { Datadog.logger }
  let(:options) { {} }
  let(:stats) do
    {
      statA: 123,
      statB: 456,
    }
  end

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
      expect(JSON.parse(flush.internal_metadata_json, symbolize_names: true)).to match(
        {
          no_signals_workaround_enabled: no_signals_workaround_enabled,
          worker_stats: stats,
          # GC stats are slightly different between ruby versions.
          gc: hash_including(:count, :total_freed_objects),
        }
      )
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

    context 'when no_signals_workaround_enabled is true' do
      let(:no_signals_workaround_enabled) { true }
      it {
        is_expected.to have_attributes(internal_metadata_json: a_string_matching('"no_signals_workaround_enabled":true'))
      }
    end

    context 'when no_signals_workaround_enabled is false' do
      let(:no_signals_workaround_enabled) { false }
      it {
        is_expected.to have_attributes(internal_metadata_json: a_string_matching('"no_signals_workaround_enabled":false'))
      }
    end
  end

  describe '#reset_after_fork' do
    let(:dummy_current_time) { Time.new(2022) }
    let(:time_provider) { class_double(Time, now: dummy_current_time) }
    let(:options) { { **super(), time_provider: class_double(Time, now: dummy_current_time) } }

    subject(:reset_after_fork) { exporter.reset_after_fork }

    it { is_expected.to be nil }

    it 'sets the last_flush_finish_at to be the current time' do
      expect { reset_after_fork }.to change { exporter.send(:last_flush_finish_at) }.from(nil).to(dummy_current_time)
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

    context 'when exporter has never flushed' do
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
