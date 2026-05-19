require "ext/libdatadog_extconf_helpers"
require "libdatadog"

RSpec.describe Datadog::LibdatadogExtconfHelpers do
  describe ".libdatadog_folder_relative_to_native_lib_folder" do
    let(:extension_folder) { "#{__dir__}/../../../ext/libdatadog_api/." }

    context "when libdatadog is available" do
      before { skip_if_libdatadog_not_supported }

      it "returns a relative path to libdatadog folder from the gem lib folder" do
        relative_path = described_class.libdatadog_folder_relative_to_native_lib_folder(extconf_folder: extension_folder)

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
            extconf_folder: extension_folder,
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

    # Use realistic paths that mirror actual gem installation structure
    let(:gem_home) { "/home/user/.gem/ruby/3.2.0" }
    let(:extconf_folder) { "#{gem_home}/gems/datadog-2.0.0/ext/datadog_profiling_native_extension" }
    let(:pkgconfig_folder) do
      "#{gem_home}/gems/libdatadog-14.0.0.1.0-x86_64-linux/vendor/libdatadog-14.0.0/x86_64-linux/" \
        "libdatadog-x86_64-unknown-linux-gnu/lib/pkgconfig"
    end

    context "when libdatadog pkgconfig_folder is nil" do
      it "returns nil" do
        result = described_class.configure_libdatadog(
          extconf_folder: extconf_folder,
          libdatadog_pkgconfig_folder: nil,
          logger: logger,
        )

        expect(result).to be_nil
      end
    end

    context "when libdatadog pkgconfig_folder is available" do
      # rubocop:disable Style/GlobalVars
      it "returns true and sets mkmf global variables including relative rpaths" do
        expect_in_fork do
          # Initialize mkmf globals as extconf.rb would
          $INCFLAGS = +""
          $LDFLAGS = +""
          $libs = +""

          result = described_class.configure_libdatadog(
            extconf_folder: extconf_folder,
            libdatadog_pkgconfig_folder: pkgconfig_folder,
            gem_dir: gem_home,
            logger: logger,
          )

          expect(result).to be true
          expect($INCFLAGS).to eq(" -I#{pkgconfig_folder}/../../include")

          libdir = "#{pkgconfig_folder}/../../lib"
          # The relative rpaths are computed from three locations:
          # 1. From native lib folder (gems/datadog-X/lib/) - needs ../../ to reach gems/
          # 2. From extensions folder (extensions/platform/api/gem/) - needs ../../../../ to reach gems/
          # 3. From bundler extensions folder (bundler/gems/extensions/platform/api/gem/) - needs ../../../../../../ to reach gems/
          libdatadog_path = "libdatadog-14.0.0.1.0-x86_64-linux/vendor/libdatadog-14.0.0/x86_64-linux/" \
            "libdatadog-x86_64-unknown-linux-gnu/lib"
          expected_ldflags =
            " -L#{libdir} -Wl,-rpath,#{libdir}" \
            " -Wl,-rpath,$$$\\\\{ORIGIN\\}/../../#{libdatadog_path}" \
            " -Wl,-rpath,$$$\\\\{ORIGIN\\}/../../../../gems/#{libdatadog_path}" \
            " -Wl,-rpath,$$$\\\\{ORIGIN\\}/../../../../../../gems/#{libdatadog_path}"
          expect($LDFLAGS).to eq(expected_ldflags)
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

  describe Datadog::LibdatadogExtconfHelpers::DumpMkmfLogOnFailure do
    describe "#mkmf_failed" do
      # Hosts the prepended module with a stub `mkmf_failed` for `super` to land in,
      # so we don't pull in real mkmf or trigger a real abort.
      let(:host_class) do
        Class.new do
          def mkmf_failed(_path)
          end
          prepend Datadog::LibdatadogExtconfHelpers::DumpMkmfLogOnFailure
        end
      end
      let(:tmp_dir) { File.realpath(Dir.mktmpdir) }
      let(:log_path) { File.join(tmp_dir, "mkmf.log") }
      let(:fake_log) do
        <<~LOG
          first irrelevant entry
          --------------------
          second irrelevant entry
          --------------------
          have_header: checking for missing.h... -------------------- no
          fake gcc invocation; fake fatal error
          --------------------
        LOG
      end

      after { FileUtils.remove_entry(tmp_dir) }
      around { |example| Dir.chdir(tmp_dir) { example.run } }
      before { $makefile_created = nil } # rubocop:disable Style/GlobalVars # mkmf usually sets this; suppress uninit warning

      context "when mkmf.log exists and no Makefile was created" do
        before { File.write(log_path, fake_log) }

        it "prints a banner with the last log entry to stderr" do
          expect { host_class.new.mkmf_failed("dummy.rb") }.to output(
            a_string_including("There was an issue setting up extension build")
              .and(including("Full failure log is at #{log_path}"))
              .and(including("have_header: checking for missing.h"))
              .and(including("fake gcc invocation; fake fatal error"))
          ).to_stderr
        end

        it "does not include earlier entries from the log" do
          expect { host_class.new.mkmf_failed("dummy.rb") }.not_to output(/first irrelevant|second irrelevant/).to_stderr
        end
      end

      context "when mkmf.log does not exist" do
        it "prints nothing" do
          expect { host_class.new.mkmf_failed("dummy.rb") }.not_to output.to_stderr
        end
      end
    end
  end
end
