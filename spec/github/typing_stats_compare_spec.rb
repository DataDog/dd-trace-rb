# frozen_string_literal: true

require "bundler"
require "fileutils"
require "open3"
require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe "typing stats comparison" do
  subject(:comparison) do
    Dir.mktmpdir("typing-stats-head") do |head_project_path|
      Dir.mktmpdir("typing-stats-base") do |base_project_path|
        create_project(head_project_path, head_rbs, head_rb)
        create_project(base_project_path, base_rbs, base_rb)

        Tempfile.create("typing-stats-head") do |head_stats_file|
          Tempfile.create("typing-stats-base") do |base_stats_file|
            head_stats_file.write(compute_stats(head_project_path))
            head_stats_file.flush
            base_stats_file.write(compute_stats(base_project_path))
            base_stats_file.flush

            run_script(
              ".github/scripts/typing_stats_compare.rb",
              {
                "CURRENT_STATS_PATH" => head_stats_file.path,
                "BASE_STATS_PATH" => base_stats_file.path,
              },
            )
          end
        end
      end
    end
  end

  def create_project(project_path, rbs, ruby_source)
    FileUtils.mkdir_p(File.join(project_path, "lib"))
    FileUtils.mkdir_p(File.join(project_path, "sig"))
    File.write(File.join(project_path, "lib/example.rb"), ruby_source)
    File.write(File.join(project_path, "sig/example.rbs"), rbs)
    File.write(
      File.join(project_path, "Steepfile"),
      <<~STEEPFILE,
        target :datadog do
          signature "sig"
          check "lib/"
        end
      STEEPFILE
    )
  end

  def compute_stats(project_path)
    run_script(
      ".github/scripts/typing_stats_compute.rb",
      {"STEEPFILE_PATH" => File.join(project_path, "Steepfile")},
      working_directory: project_path,
    )
  end

  def run_script(script, environment, working_directory: Dir.pwd)
    environment = environment.merge(
      "BUNDLE_GEMFILE" => Bundler.default_gemfile.expand_path.to_s
    )

    output, status = Open3.capture2e(
      environment,
      "bundle", "exec", "ruby", File.expand_path(script),
      chdir: working_directory
    )
    raise output unless status.success?

    output
  end

  let(:base_rb) { "" }
  let(:head_rb) { "" }

  context "when an untyped declaration is introduced" do
    let(:base_rbs) do
      <<~RBS
        class Example
          def untyped_method: () -> untyped
        end
      RBS
    end

    let(:head_rbs) do
      <<~RBS
        class Example
          attr_reader other: untyped
          def untyped_method: () -> untyped
        end
      RBS
    end

    it "reports the declaration at its current line" do
      is_expected.to include("sig/example.rbs:2\n└── attr_reader other: untyped")
    end
  end

  context "when a typed declaration is introduced before an untyped method" do
    let(:base_rbs) do
      <<~RBS
        class Example
          def untyped_method: () -> untyped
        end
      RBS
    end

    let(:head_rbs) do
      <<~RBS
        class Example
          attr_reader inserted: String
          def untyped_method: () -> untyped
        end
      RBS
    end

    it "does not report declarations whose line numbers changed" do
      is_expected.to eq("")
    end
  end

  context "when the same declaration moves to another namespace" do
    let(:base_rbs) do
      <<~RBS
        class First
          def call: () -> untyped
        end

        class Second
          def call: () -> String
        end
      RBS
    end

    let(:head_rbs) do
      <<~RBS
        class First
          def call: () -> String
        end

        class Second
          def call: () -> untyped
        end
      RBS
    end

    it "reports the introduced and cleared declarations" do
      is_expected.to include("introduces **1** untyped method, and clears **1** untyped method")
    end
  end

  context "when a line is introduced before a steep:ignore comment" do
    let(:base_rbs) do
      <<~RBS
        class Example
        end
      RBS
    end

    let(:head_rbs) { base_rbs }

    let(:base_rb) do
      <<~RUBY
        class Example
          value.call # steep:ignore NoMethod
        end
      RUBY
    end

    let(:head_rb) do
      <<~RUBY
        class Example
          inserted = true
          value.call # steep:ignore NoMethod
        end
      RUBY
    end

    it "does not report the moved comment" do
      is_expected.to eq("")
    end
  end

  context "when a steep:ignore comment is introduced" do
    let(:base_rbs) do
      <<~RBS
        class Example
        end
      RBS
    end

    let(:head_rbs) { base_rbs }

    let(:base_rb) do
      <<~RUBY
        class Example
        end
      RUBY
    end

    let(:head_rb) do
      <<~RUBY
        class Example
          value.call # steep:ignore NoMethod
        end
      RUBY
    end

    it "reports the comment at its current line" do
      is_expected.to include("introduces **1** <code>steep:ignore</code> comment")
      is_expected.to include("lib/example.rb:2")
    end
  end

  context "when the same steep:ignore comment moves to another namespace" do
    let(:base_rbs) do
      <<~RBS
        class First
        end
        class Second
        end
      RBS
    end

    let(:head_rbs) { base_rbs }

    let(:base_rb) do
      <<~RUBY
        class First
          value.call # steep:ignore NoMethod
        end

        class Second
          value.call
        end
      RUBY
    end

    let(:head_rb) do
      <<~RUBY
        class First
          value.call
        end

        class Second
          value.call # steep:ignore NoMethod
        end
      RUBY
    end

    it "reports the introduced and cleared comments" do
      is_expected.to include("introduces **1** <code>steep:ignore</code> comment, and clears **1** <code>steep:ignore</code> comment")
    end
  end

  context "when the same steep:ignore comment moves to another method" do
    let(:base_rbs) do
      <<~RBS
        class Example
        end
      RBS
    end

    let(:head_rbs) { base_rbs }

    let(:base_rb) do
      <<~RUBY
        class Example
          def first
            value.call # steep:ignore NoMethod
          end

          def second
            value.call
          end
        end
      RUBY
    end

    let(:head_rb) do
      <<~RUBY
        class Example
          def first
            value.call
          end

          def second
            value.call # steep:ignore NoMethod
          end
        end
      RUBY
    end

    it "reports the introduced and cleared comments" do
      is_expected.to include("introduces **1** <code>steep:ignore</code> comment, and clears **1** <code>steep:ignore</code> comment")
    end
  end
end
