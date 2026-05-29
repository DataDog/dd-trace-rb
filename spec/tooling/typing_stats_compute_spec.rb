# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tempfile"
require "tmpdir"

RSpec.describe "typing_stats_compute.rb" do
  let(:compute_script_path) { File.expand_path("../../.github/scripts/typing_stats_compute.rb", __dir__) }
  let(:compare_script_path) { File.expand_path("../../.github/scripts/typing_stats_compare.rb", __dir__) }

  def compute_stats(source)
    Dir.mktmpdir("typing-stats") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "sig"))
      File.write(File.join(dir, "Steepfile"), <<~STEEPFILE)
        target :datadog do
          signature "sig"
          check "lib"
        end
      STEEPFILE
      File.write(File.join(dir, "lib", "example.rb"), source)

      env = {"STEEPFILE_PATH" => File.join(dir, "Steepfile")}
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, compute_script_path, chdir: dir)
      expect(status).to be_success, stderr
      JSON.parse(stdout, symbolize_names: true)
    end
  end

  def run_compare(head_stats, base_stats)
    with_file(JSON.dump(head_stats)) do |head_stats_path|
      with_file(JSON.dump(base_stats)) do |base_stats_path|
        with_file("") do |renamed_paths_path|
          env = {
            "CURRENT_STATS_PATH" => head_stats_path,
            "BASE_STATS_PATH" => base_stats_path,
            "RENAMED_PATHS_PATH" => renamed_paths_path
          }

          stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, compare_script_path)
          expect(status).to be_success, stderr
          stdout
        end
      end
    end
  end

  def with_file(content)
    Tempfile.create("typing-stats") do |file|
      file.write(content)
      file.close
      yield file.path
    end
  end

  it "does not match unrelated block steep:ignore comments in the same file" do
    base_stats = compute_stats(<<~RUBY)
      # steep:ignore:start
      base_call
      # steep:ignore:end
    RUBY
    head_stats = compute_stats(<<~RUBY)
      head_call

      # steep:ignore:start
      head_call
      # steep:ignore:end
    RUBY

    expect(run_compare(head_stats, base_stats)).to include("<code>steep:ignore</code> comments (<strong>+1-1</strong>)")
  end

  it "preserves single-line steep:ignore ignored source" do
    stats = compute_stats(<<~RUBY)
      single_call # steep:ignore
    RUBY

    expect(stats[:steep_ignore_comments].first[:comparison_key]).to include(
      source: "# steep:ignore",
      ignored_source: "single_call # steep:ignore"
    )
  end
end
