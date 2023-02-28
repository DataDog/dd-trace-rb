RSpec.describe Datadog::Profiling::Flush do
  describe '.new' do
    let(:start) { instance_double(Time, 'start time') }
    let(:finish) { instance_double(Time, 'finish time') }
    let(:pprof_file_name) { 'the_pprof_file_name.pprof' }
    let(:pprof_data) { 'the_pprof_data' }
    let(:code_provenance_file_name) { 'the_code_provenance_file_name.json' }
    let(:code_provenance_data) { 'the_code_provenance_data' }
    let(:tags_as_array) { [%w[tag_a value_a], %w[tag_b value_b]] }

    subject(:flush) do
      described_class.new(
        start: start,
        finish: finish,
        pprof_file_name: pprof_file_name,
        pprof_data: pprof_data,
        code_provenance_file_name: code_provenance_file_name,
        code_provenance_data: code_provenance_data,
        tags_as_array: tags_as_array,
      )
    end

    it do
      expect(flush).to have_attributes(
        start: start,
        finish: finish,
        pprof_file_name: pprof_file_name,
        pprof_data: pprof_data,
        code_provenance_file_name: code_provenance_file_name,
        code_provenance_data: code_provenance_data,
        tags_as_array: tags_as_array,
      )
    end
  end
end
