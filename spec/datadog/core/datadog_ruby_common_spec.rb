# frozen_string_literal: true

RSpec.describe 'datadog_ruby_common helpers' do
  let(:profiling_folder) { File.join(__dir__, '../../../ext/datadog_profiling_native_extension') }
  let(:libdatadog_api_folder) { File.join(__dir__, '../../../ext/libdatadog_api') }

  ['datadog_ruby_common.c', 'datadog_ruby_common.h'].each do |filename|
    describe filename do
      it 'is identical between profiling and libdatadog_api' do
        profiling_content = File.read(File.join(profiling_folder, filename))
        libdatadog_api_content = File.read(File.join(libdatadog_api_folder, filename))

        expect(profiling_content).to eq(libdatadog_api_content), "#{filename} files are not identical"
      end
    end
  end
end
