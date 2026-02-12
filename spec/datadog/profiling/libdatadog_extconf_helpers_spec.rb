require "ext/libdatadog_extconf_helpers"
require "libdatadog"
require "datadog/profiling/spec_helper"

# TODO: This should be extracted out once the test suite setup is updated to build libdatadog_api separate from profiling
RSpec.describe Datadog::LibdatadogExtconfHelpers do
  describe ".libdatadog_folder_relative_to_native_lib_folder" do
    let(:extension_folder) { "#{__dir__}/../../../ext/datadog_profiling_native_extension/." }

    context "when libdatadog is available" do
      before do
        skip_if_profiling_not_supported
        if PlatformHelpers.mac? && Libdatadog.pkgconfig_folder.nil? && ENV["LIBDATADOG_VENDOR_OVERRIDE"].nil?
          skip "Needs LIBDATADOG_VENDOR_OVERRIDE pointing at a valid libdatadog build on macOS"
        end
      end

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
      before do
        skip_if_profiling_not_supported
        if PlatformHelpers.mac? && Libdatadog.pkgconfig_folder.nil? && ENV["LIBDATADOG_VENDOR_OVERRIDE"].nil?
          skip "Needs LIBDATADOG_VENDOR_OVERRIDE pointing at a valid libdatadog build on macOS"
        end
      end

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

  describe ".pkg_config_missing?" do
    subject(:pkg_config_missing) { described_class.pkg_config_missing?(command: command) }

    before do
      skip_if_profiling_not_supported
    end

    context "when command is not available" do
      let(:command) { nil }

      it { is_expected.to be true }
    end

    # This spec is semi-realistic, because it actually calls into the pkg-config external process.
    #
    # We know pkg-config must be available on the machine running the tests because otherwise profiling would not be
    # supported (and thus `skip_if_profiling_not_supported` would've been triggered).
    #
    # We could also mock the entire interaction, but this seemed like a simple enough way to go.
    context "when command is available" do
      before do
        # This helper is designed to be called from extconf.rb, which requires mkmf, which defines xsystem.
        # When executed in RSpec, mkmf is not required, so we replace it with the regular system call.
        without_partial_double_verification do
          expect(described_class).to receive(:xsystem) { |*args| system(*args) }
        end
      end

      context "and pkg-config can successfully be called" do
        let(:command) { "pkg-config" }

        it { is_expected.to be false }
      end

      context "and pkg-config cannot be called" do
        let(:command) { "does-not-exist" }

        it { is_expected.to be true }
      end
    end
  end

  describe ".load_libdatadog_or_get_issue" do
    subject(:load_libdatadog_or_get_issue) { described_class.load_libdatadog_or_get_issue }

    before do
      skip_if_profiling_not_supported
    end

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
