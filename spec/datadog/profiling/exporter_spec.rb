# typed: false

require 'datadog/profiling/exporter'
require 'datadog/profiling/old_recorder'
require 'datadog/profiling/collectors/code_provenance'
require 'datadog/core/logger'

RSpec.describe Datadog::Profiling::Exporter do
  subject(:exporter) do
    described_class.new(pprof_recorder: pprof_recorder, code_provenance_collector: code_provenance_collector)
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

  describe '#flush' do
    subject(:flush) { exporter.flush }

    it 'returns a flush containing the data from the recorders' do
      expect(flush).to have_attributes(
        start: start,
        finish: finish,
        pprof_file_name: 'rubyprofile.pprof.gz',
        code_provenance_file_name: 'code-provenance.json.gz',
        tags_as_array: array_including(%w[language ruby], ['pid', Process.pid.to_s]),
      )
      expect(Datadog::Core::Utils::Compression.gunzip(flush.pprof_data)).to eq pprof_data
      expect(Datadog::Core::Utils::Compression.gunzip(flush.code_provenance_data)).to eq code_provenance_data
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

  describe '#empty?' do
    it 'delegates to the pprof_recorder' do
      expect(pprof_recorder).to receive(:empty?).and_return(:empty_result)

      expect(exporter.empty?).to be :empty_result
    end
  end
end
