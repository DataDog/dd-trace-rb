require "spec_helper"
require "datadog/profiling/spec_helper"

RSpec.describe "Datadog::Profiling load_native_extension" do
  before { skip_if_profiling_not_supported(self) }

  subject(:load_native_extension) do
    load "#{__dir__}/../../../lib/datadog/profiling/load_native_extension.rb"
  end

  context "when native extension can be found inside lib" do
    it "loads the native extension from lib/" do
      expect(Datadog::Profiling::Loader).to receive(:_native_load) do |full_file_path|
        absolute_path = File.absolute_path(full_file_path)
        expect(absolute_path).to include("lib/datadog_profiling_native_extension")
      end

      load_native_extension
    end
  end

  context "when native extension cannot be found inside lib" do
    let(:extension_dir) { Gem.loaded_specs["datadog"].extension_dir }

    before do
      expect(File).to receive(:exist?) do |full_file_path|
        absolute_path = File.absolute_path(full_file_path)

        if absolute_path.include?("lib/datadog_profiling_native_extension")
          false
        elsif absolute_path.include?(extension_dir)
          true
        else
          raise "Unexpected path in mock: #{full_file_path}"
        end
      end.twice
    end

    it "loads the native extension from the extension dir" do
      expect(Datadog::Profiling::Loader).to receive(:_native_load) do |full_file_path|
        absolute_path = File.absolute_path(full_file_path)
        expect(absolute_path).to include(extension_dir)
      end

      load_native_extension
    end
  end

  context "when native extension cannot be found on either directory" do
    before do
      expect(File).to receive(:exist?).twice.and_return(false)
    end

    it "tries to load the native extension from lib/" do
      expect(Datadog::Profiling::Loader).to receive(:_native_load) do |full_file_path|
        absolute_path = File.absolute_path(full_file_path)
        expect(absolute_path).to include("lib/datadog_profiling_native_extension")
      end

      load_native_extension
    end
  end

  context "when the loader reports an error" do
    it "raises an exception" do
      expect(Datadog::Profiling::Loader).to receive(:_native_load).and_return([:error, "some error"])

      expect do
        load_native_extension
      end.to raise_error(/Failure to load datadog_profiling_native_extension.*due to some error/)
    end
  end
end
