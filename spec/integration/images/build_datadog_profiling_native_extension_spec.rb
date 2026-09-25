require "spec_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "building the profiling extension for a local datadog gem" do
  it "prelocks first-party dependencies before installing" do
    Dir.mktmpdir do |dir|
      bin_dir = File.join(dir, "bin")
      gem_dir = File.join(dir, "gem")
      commands_path = File.join(dir, "commands")
      FileUtils.mkdir_p(bin_dir)
      FileUtils.mkdir_p(gem_dir)

      %w[ruby bundle].each do |command|
        path = File.join(bin_dir, command)
        File.write(path, "#!/bin/sh\necho #{command} \"$@\" >> \"$COMMANDS_PATH\"\n")
        FileUtils.chmod("+x", path)
      end

      script = File.expand_path("../../../integration/images/include/build_datadog_profiling_native_extension.rb", __dir__)
      _, stderr, status = Open3.capture3(
        {"COMMANDS_PATH" => commands_path, "DD_DEMO_ENV_GEM_LOCAL_DATADOG" => gem_dir, "PATH" => "#{bin_dir}:#{ENV.fetch("PATH")}"},
        RbConfig.ruby,
        script,
      )

      expect(status).to be_success, stderr
      expect(File.read(commands_path)).to include("ruby -r./tasks/prelock -e Prelock.call(\"Gemfile\")")
    end
  end
end
