# frozen_string_literal: true

require "libdatadog"

RSpec.describe "datadog_ruby_common" do
  let(:profiling_folder) { File.join(__dir__, "../../../ext/datadog_profiling_native_extension") }
  let(:libdatadog_api_folder) { File.join(__dir__, "../../../ext/libdatadog_api") }

  describe "copy-paste synchronization" do
    ["datadog_ruby_common.c", "datadog_ruby_common.h"].each do |filename|
      describe filename do
        it "is identical between profiling and libdatadog_api" do
          profiling_content = File.read(File.join(profiling_folder, filename))
          libdatadog_api_content = File.read(File.join(libdatadog_api_folder, filename))

          expect(profiling_content).to eq(libdatadog_api_content), "#{filename} files are not identical"
        end
      end
    end
  end

  describe "libdatadog version verification" do
    before { skip_if_libdatadog_not_supported }

    let(:extension_name) { "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}" }

    context "when libdatadog version does not match the compiled version" do
      it "raises an error with a helpful message" do
        # Use Open3 to spawn a fresh Ruby process (not fork) so the extension isn't pre-loaded
        require "open3"

        _, stderr, status = Open3.capture3(
          RbConfig.ruby,
          "-e",
          <<~RUBY
            require 'libdatadog'
            Libdatadog.send(:remove_const, :VERSION)
            Libdatadog.const_set(:VERSION, '0.0.0.0.0')
            require '#{extension_name}'
          RUBY
        )

        expect(status.success?).to be(false), "Expected process to fail but it succeeded. stderr: #{stderr}"
        expect(stderr).to include(
          "The `datadog` gem needs to be reinstalled whenever the `libdatadog` gem version is changed. " \
            "The currently-installed version of `datadog` was built to work with `libdatadog` gem version #{Libdatadog::VERSION} " \
            "but the currently-loaded version of `libdatadog` is 0.0.0.0.0. " \
            "To fix this, reinstall the `datadog` gem (e.g. `bundle exec gem pristine datadog`) " \
            "or contact Datadog support for help at <https://docs.datadoghq.com/help/>."
        )
      end
    end
  end
end
