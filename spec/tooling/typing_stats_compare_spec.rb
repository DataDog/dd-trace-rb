# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tempfile"

RSpec.describe "typing_stats_compare.rb" do
  subject(:output) { run_compare(head_stats, base_stats, renamed_paths) }

  let(:script_path) { File.expand_path("../../.github/scripts/typing_stats_compare.rb", __dir__) }
  let(:base_stats) { stats }
  let(:head_stats) { stats }
  let(:renamed_paths) { "" }

  def stats(overrides = {})
    {
      total_files_size: 1,
      ignored_files: [],
      steep_ignore_comments: [],
      untyped_methods: [],
      partially_typed_methods: [],
      typed_methods_size: 1,
      untyped_others: [],
      partially_typed_others: [],
      typed_others_size: 1
    }.merge(overrides)
  end

  def declaration(path:, line:, source: "def self?.call: (untyped value) -> untyped", context: ["::Datadog", "::Datadog::Example"])
    {
      path: path,
      line: line,
      line_content: source,
      comparison_key: {type: "rbs_declaration", path: path, context: context, source: source}
    }
  end

  def steep_ignore(line:, path: "lib/datadog/example.rb", source: "# steep:ignore", ignored_source: "call # steep:ignore")
    {
      path: path,
      line: line,
      comparison_key: {type: "steep_ignore", path: path, source: source, ignored_source: ignored_source}
    }
  end

  def run_compare(head_stats, base_stats, renamed_paths)
    with_file(JSON.dump(head_stats)) do |head_stats_path|
      with_file(JSON.dump(base_stats)) do |base_stats_path|
        with_file(renamed_paths) do |renamed_paths_path|
          env = {
            "CURRENT_STATS_PATH" => head_stats_path,
            "BASE_STATS_PATH" => base_stats_path
          }
          env["RENAMED_PATHS_PATH"] = renamed_paths_path

          stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, script_path)
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

  it "prints nothing when stats are unchanged" do
    is_expected.to eq("")
  end

  it "reports ignored files changes" do
    base = stats(total_files_size: 10, ignored_files: ["lib/datadog/base.rb"])
    head = stats(total_files_size: 10, ignored_files: ["lib/datadog/head.rb"])

    expect(run_compare(head, base, "")).to include("This PR introduces **1** ignored file, and clears **1** ignored file.")
      .and include("Ignored files (<strong>+1-1</strong>)")
      .and include("lib/datadog/head.rb")
      .and include("lib/datadog/base.rb")
  end

  it "reports cleared RBS and steep:ignore findings" do
    base = stats(
      steep_ignore_comments: [steep_ignore(line: 18)],
      untyped_methods: [declaration(path: "sig/datadog/example.rbs", line: 14)]
    )

    expect(run_compare(stats, base, "")).to include("clears **1** <code>steep:ignore</code> comment")
      .and include("clears **1** untyped method")
  end

  it "ignores RBS line moves, follows renames, and ignores steep:ignore line moves" do
    base = stats(
      partially_typed_methods: [declaration(path: "sig/datadog/base_name.rbs", line: 10)],
      partially_typed_others: [declaration(path: "sig/datadog/example.rbs", line: 12, source: "EXAMPLE_OPTIONS: ::Hash[::Symbol, untyped]")],
      steep_ignore_comments: [steep_ignore(line: 8)]
    )
    head = stats(
      partially_typed_methods: [declaration(path: "sig/datadog/head_name.rbs", line: 25)],
      partially_typed_others: [declaration(path: "sig/datadog/example.rbs", line: 30, source: "EXAMPLE_OPTIONS: ::Hash[::Symbol, untyped]")],
      steep_ignore_comments: [steep_ignore(line: 18)]
    )

    expect(run_compare(head, base, "R097\tsig/datadog/base_name.rbs\tsig/datadog/head_name.rbs\n")).to eq("")
  end

  it "compares RBS and steep:ignore findings as multisets" do
    repeated = declaration(path: "sig/datadog/example.rbs", line: 10)
    base = stats(partially_typed_methods: [repeated, repeated.merge(line: 20)])
    head = stats(partially_typed_methods: [repeated.merge(line: 30)])

    expect(run_compare(head, base, "")).to include("Partially typed methods (<strong>+0-1</strong>)")
  end

  it "does not match RBS declarations across different owners" do
    base = stats(untyped_methods: [declaration(path: "sig/datadog/example.rbs", line: 10, context: ["::Datadog::BaseExample"])])
    head = stats(untyped_methods: [declaration(path: "sig/datadog/example.rbs", line: 14, context: ["::Datadog::HeadExample"])])

    expect(run_compare(head, base, "")).to include("Untyped methods (<strong>+1-1</strong>)")
  end

  it "does not match steep:ignore comments across different ignored source" do
    base = stats(steep_ignore_comments: [steep_ignore(line: 8, ignored_source: "base_call # steep:ignore")])
    head = stats(steep_ignore_comments: [steep_ignore(line: 18, ignored_source: "head_call # steep:ignore")])

    expect(run_compare(head, base, "")).to include("<code>steep:ignore</code> comments (<strong>+1-1</strong>)")
  end

  it "still reports introduced RBS and steep:ignore findings" do
    head = stats(
      steep_ignore_comments: [steep_ignore(line: 18)],
      untyped_methods: [declaration(path: "sig/datadog/example.rbs", line: 14)]
    )

    expect(run_compare(head, stats, "")).to include("introduces **1** <code>steep:ignore</code> comment")
      .and include("introduces **1** untyped method")
  end
end
