require 'ddtrace/profiling/pprof/code_identification'

RSpec.describe Datadog::Profiling::Pprof::CodeIdentification do
  let(:mapping_id_for) { instance_double(Proc, 'mapping_id_for') }

  subject(:code_identification) { described_class.new(mapping_id_for: mapping_id_for) }

  describe '#mapping_for' do
    context 'when given a path from a loaded gem' do
      let(:rspec_file_path) { RSpec.method(:describe).source_location.first }
      let(:rspec_version) { RSpec::Core::Version::STRING }
      let(:rspec_full_name) { "rspec-core-#{rspec_version}" }
      let(:rspec_path) { rspec_file_path[0...(rspec_file_path.rindex(rspec_full_name) + rspec_full_name.size)] }

      it 'returns the mapping for that gem' do
        expected_mapping_id = rand(1000)

        allow(mapping_id_for)
          .to receive(:call).with(filename: rspec_path, build_id: rspec_full_name)
                            .and_return(expected_mapping_id)

        expect(code_identification.mapping_for(rspec_file_path)).to be expected_mapping_id
      end

      it 'caches the result for that path' do
        expect(mapping_id_for).to receive(:call).and_return(12345).once

        code_identification.mapping_for(rspec_file_path)
        code_identification.mapping_for(rspec_file_path)
      end

      context 'when given a path that has not been loaded' do
        let(:not_loaded_file) { "#{rspec_path}/not_loaded.rb" }

        it 'returns 0' do
          expect(code_identification.mapping_for(not_loaded_file)).to be 0
        end
      end
    end

    context 'when given a path from the standard library' do
      let(:set_file_path) { Set.new.method(:add).source_location.first }
      let(:standard_library_path) { set_file_path[0...(set_file_path.rindex('set.rb') - 1)] }

      it 'returns the mapping for the standard library' do
        expected_mapping_id = rand(1000)

        allow(mapping_id_for)
          .to receive(:call).with(filename: standard_library_path, build_id: 'ruby-standard-library')
                            .and_return(expected_mapping_id)

        expect(code_identification.mapping_for(set_file_path)).to be expected_mapping_id
      end

      it 'caches the result for that path' do
        expect(mapping_id_for).to receive(:call).and_return(12345).once

        code_identification.mapping_for(set_file_path)
        code_identification.mapping_for(set_file_path)
      end

      context 'when given a path that has not been loaded' do
        let(:not_loaded_file) { "#{standard_library_path}/not_loaded.rb" }

        it 'returns 0' do
          expect(code_identification.mapping_for(not_loaded_file)).to be 0
        end
      end
    end

    context 'when given something which is not a file' do
      # rubocop:disable Style/EvalWithLocation
      let(:not_a_path) { eval('proc {}').source_location.first }
      # rubocop:enable Style/EvalWithLocation

      it 'returns 0' do
        expect(code_identification.mapping_for(not_a_path)).to be 0
      end
    end

    context 'when given a path that is not in the standard library or in a loaded gem' do
      let(:this_file_path) { __FILE__ }

      it 'returns 0' do
        expect(code_identification.mapping_for(this_file_path)).to be 0
      end
    end
  end
end
