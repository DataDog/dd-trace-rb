require "ext/libdatadog_extconf_helpers"
require "libdatadog"

RSpec.describe Datadog::LibdatadogExtconfHelpers do
  describe ".libdatadog_folder_relative_to_native_lib_folder" do
    let(:extension_folder) { "#{__dir__}/../../../ext/libdatadog_api/." }

    context "when libdatadog is available" do
      before { skip_if_libdatadog_not_supported }

      it "returns a relative path to libdatadog folder from the gem lib folder" do
        relative_path = described_class.libdatadog_folder_relative_to_native_lib_folder(current_folder: extension_folder)

        libdatadog_extension = RbConfig::CONFIG["SOEXT"] || raise("Missing SOEXT for current platform")

        gem_lib_folder = "#{Gem.loaded_specs["datadog"].gem_dir}/lib"
        full_libdatadog_path = "#{gem_lib_folder}/#{relative_path}/libdatadog_profiling.#{libdatadog_extension}"

        expect(relative_path).to start_with("../")
        expect(File.exist?(full_libdatadog_path))
          .to be(true), "Libdatadog not available in expected path: #{full_libdatadog_path.inspect}"
      end
    end

    context "when libdatadog is unsupported" do
      it do
        expect(
          described_class.libdatadog_folder_relative_to_native_lib_folder(
            current_folder: extension_folder,
            libdatadog_pkgconfig_folder: nil
          )
        ).to be nil
      end
    end
  end

  describe ".libdatadog_folder_relative_to_ruby_extensions_folders" do
    context "when libdatadog is available" do
      before { skip_if_libdatadog_not_supported }

      it "returns a relative path to libdatadog folder from the ruby extensions folders" do
        extensions_relative, bundler_extensions_relative =
          described_class.libdatadog_folder_relative_to_ruby_extensions_folders

        libdatadog_extension = RbConfig::CONFIG["SOEXT"] || raise("Missing SOEXT for current platform")
        libdatadog = "libdatadog_profiling.#{libdatadog_extension}"

        expect(extensions_relative).to start_with("../")
        expect(bundler_extensions_relative).to start_with("../")

        extensions_full =
          "#{Gem.dir}/extensions/platform/extension_api_version/datadog_version/#{extensions_relative}/#{libdatadog}"
        bundler_extensions_full =
          "#{Gem.dir}/bundler/gems/extensions/platform/extension_api_version/datadog_version/" \
          "#{bundler_extensions_relative}/#{libdatadog}"

        expect(File.exist?(Pathname.new(extensions_full).cleanpath.to_s))
          .to be(true), "Libdatadog not available in expected path: #{extensions_full.inspect}"
        expect(File.exist?(Pathname.new(bundler_extensions_full).cleanpath.to_s))
          .to be(true), "Libdatadog not available in expected path: #{bundler_extensions_full.inspect}"
      end
    end

    context "when libdatadog is unsupported" do
      it do
        expect(
          described_class.libdatadog_folder_relative_to_ruby_extensions_folders(libdatadog_pkgconfig_folder: nil)
        ).to be nil
      end
    end
  end

  describe "::LIBDATADOG_VERSION" do
    it "must match the version restriction set on the gemspec" do
      # This test is expected to break when the libdatadog version on the .gemspec is updated but we forget to update
      # the version on the `libdatadog_extconf_helpers.rb` file. Kindly keep them in sync! :)
      expect(described_class::LIBDATADOG_VERSION).to eq(
        Gem.loaded_specs["datadog"].dependencies.find { |dependency| dependency.name == "libdatadog" }.requirement.to_s
      )
    end
  end

  describe ".configure_libdatadog" do
    let(:logger) { double("logger", message: nil) }

    context "when libdatadog pkgconfig_folder is nil" do
      it "returns nil" do
        result = described_class.configure_libdatadog(
          libdatadog_pkgconfig_folder: nil,
          logger: logger,
        )

        expect(result).to be_nil
      end
    end

    context "when libdatadog pkgconfig_folder is available" do
      let(:pkgconfig_folder) { "/path/to/gems/libdatadog/vendor/libdatadog/lib/pkgconfig" }

      # rubocop:disable Style/GlobalVars
      it "returns true and sets mkmf global variables" do
        expect_in_fork do
          # Initialize mkmf globals as extconf.rb would
          $INCFLAGS = +""
          $LDFLAGS = +""
          $libs = +""

          result = described_class.configure_libdatadog(
            libdatadog_pkgconfig_folder: pkgconfig_folder,
            logger: logger,
          )

          expect(result).to be true
          expect($INCFLAGS).to eq(" -I#{pkgconfig_folder}/../../include")

          libdir = "#{pkgconfig_folder}/../../lib"
          expect($LDFLAGS).to eq(" -L#{libdir} -Wl,-rpath,#{libdir}")
          expect($libs).to eq(" -ldatadog_profiling")
        end
      end
      # rubocop:enable Style/GlobalVars
    end
  end

  describe ".load_libdatadog_or_get_issue" do
    subject(:load_libdatadog_or_get_issue) { described_class.load_libdatadog_or_get_issue }

    before { skip_if_libdatadog_not_supported }

    context "when libdatadog gem fails to load" do
      before do
        expect(described_class).to receive(:require).and_raise(LoadError.new("Test error"))
      end

      it "returns an error message with the exception details" do
        expect(load_libdatadog_or_get_issue).to eq("There was an error loading `libdatadog`: LoadError Test error")
      end
    end

    context "when libdatadog gem loads successfully but pkgconfig_folder is nil" do
      before do
        expect(described_class).to receive(:try_loading_libdatadog).and_return(nil)
        expect(Libdatadog).to receive(:pkgconfig_folder).and_return(nil)
        expect(Libdatadog).to receive(:current_platform).and_return("testplatform")
        expect(Libdatadog).to receive(:available_binaries).and_return(["testbinary1", "testbinary2"])
      end

      it "returns an error message about missing platform binaries" do
        expect(load_libdatadog_or_get_issue).to eq(
          "The `libdatadog` gem installed on your system is missing binaries for your platform variant. " \
          "Your platform: `testplatform`; available binaries: `testbinary1`, `testbinary2`"
        )
      end
    end

    context "when libdatadog gem loads successfully and pkgconfig_folder is available" do
      before do
        expect(described_class).to receive(:try_loading_libdatadog).and_return(nil)
        expect(Libdatadog).to receive(:pkgconfig_folder).and_return("/path/to/pkgconfig")
      end

      it "returns nil (no issues)" do
        expect(load_libdatadog_or_get_issue).to be_nil
      end
    end
  end
end
