require "spec_helper"
require "rake"
require "tmpdir"
require "stringio"
require_relative "../../tasks/appraisal_conversion"

RSpec.describe "GitHub batch tasks" do
  let(:runner) { Object.new.extend(Rake::DSL) }
  let(:task_file) { File.expand_path("../../tasks/github.rake", __dir__) }

  around do |example|
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    runner.instance_eval(File.read(task_file), task_file)
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) { example.run }
    end
  ensure
    Rake.application = previous_application
  end

  def invoke(name)
    Rake::Task["github:#{name}"].invoke
  end

  describe "batch generation" do
    let(:data) do
      output = StringIO.new
      allow($stdout).to receive(:write) { |text| output.write(text) }
      invoke("generate_batches")
      JSON.parse(output.string)
    end

    before do
      File.write("Matrixfile", <<~RUBY)
        {
          "main" => {"" => "✅ #{RUBY_VERSION[0..2]}", "old" => "✅ 0.0"},
          "rails" => {"rails" => "✅ #{RUBY_VERSION[0..2]}"},
          "rack" => {"rails" => "✅ #{RUBY_VERSION[0..2]}"},
          "mongodb" => {"mongo" => "✅ #{RUBY_VERSION[0..2]}"},
        }
      RUBY
      allow(AppraisalConversion).to receive(:to_bundle_gemfile) do |group|
        raise "missing appraisal" if group.empty?

        "gemfiles/#{group}.gemfile"
      end
      allow(AppraisalConversion).to receive(:parent_gemfile).and_return("gemfiles/base.gemfile")
    end

    it "emits every selected task and unique Gemfile from both batch types" do
      standard = data.fetch("batches").fetch("include").flat_map { |batch| batch.fetch("tasks") }
      misc = data.fetch("misc").fetch("include").flat_map { |batch| batch.fetch("tasks") }

      expect(standard.map { |task| task.fetch("task") }).to eq(%w[main rails rack])
      expect(misc.map { |task| task.fetch("task") }).to eq(["mongodb"])
      expect(data.fetch("all")).to match_array(standard + misc)
      expect(data.fetch("gemfiles")).to eq(%w[gemfiles/base.gemfile gemfiles/mongo.gemfile gemfiles/rails.gemfile])
      expect(standard.first).to include("group" => "", "gemfile" => "gemfiles/base.gemfile")
    end

    it "uses the base Gemfile when a selected appraisal is absent" do
      allow(AppraisalConversion).to receive(:to_bundle_gemfile).with("rails").and_raise("missing appraisal")

      expect(data.fetch("all").select { |task| task.fetch("group") == "rails" }).to all(
        include("gemfile" => "gemfiles/base.gemfile")
      )
      expect(data.fetch("gemfiles")).to eq(%w[gemfiles/base.gemfile gemfiles/mongo.gemfile])
    end
  end

  describe "batch installation" do
    let(:tasks) do
      [
        {"task" => "rails", "gemfile" => "gemfiles/rails.gemfile"},
        {"task" => "rack", "gemfile" => "gemfiles/rails.gemfile"},
        {"task" => "mongodb", "gemfile" => "gemfiles/mongo.gemfile"},
      ]
    end

    it "checks or installs each distinct batch Gemfile outside the active bundle" do
      commands = []
      allow(runner).to receive(:sh) do |environment, command|
        commands << [environment.fetch("BUNDLE_GEMFILE"), command]
      end
      expect(Bundler).to receive(:with_unbundled_env).twice.and_call_original

      ClimateControl.modify("BATCHED_TASKS" => JSON.generate(tasks)) { invoke("run_batch_build") }

      expect(commands).to eq([
        ["gemfiles/rails.gemfile", "bundle check || bundle install"],
        ["gemfiles/mongo.gemfile", "bundle check || bundle install"],
      ])
    end

    it "retries transient installation failures" do
      attempts = 0
      allow(runner).to receive(:sh) do
        attempts += 1
        raise "network failure" if attempts == 1
      end
      allow(runner).to receive(:rake_output_message)
      allow(runner).to receive(:sleep)

      ClimateControl.modify("BATCHED_TASKS" => JSON.generate(tasks.first(1))) { invoke("run_batch_build") }

      expect(attempts).to eq(2)
    end
  end

  describe "matrix bundle validation" do
    it "checks the base and every selected Gemfile once without installing" do
      commands = []
      allow(runner).to receive(:sh) do |environment, command|
        commands << [environment.fetch("BUNDLE_GEMFILE"), command]
      end
      expect(Bundler).to receive(:with_unbundled_env).exactly(3).times.and_call_original

      ClimateControl.modify(
        "BUNDLE_GEMFILE" => "gemfiles/base.gemfile",
        "GEMFILES" => JSON.generate([
          "gemfiles/rails.gemfile",
          File.expand_path("gemfiles/base.gemfile"),
          "gemfiles/mongo.gemfile",
          "gemfiles/rails.gemfile",
        ]),
      ) { invoke("check_matrix_bundle") }

      expect(commands).to eq([
        ["gemfiles/base.gemfile", "bundle check"],
        ["gemfiles/rails.gemfile", "bundle check"],
        ["gemfiles/mongo.gemfile", "bundle check"],
      ])
    end

    it "fails when a selected bundle is incomplete" do
      allow(runner).to receive(:sh).with({"BUNDLE_GEMFILE" => "gemfiles/base.gemfile"}, "bundle check")
      allow(runner).to receive(:sh).with({"BUNDLE_GEMFILE" => "gemfiles/rails.gemfile"}, "bundle check").and_raise("missing gems")

      ClimateControl.modify(
        "BUNDLE_GEMFILE" => "gemfiles/base.gemfile",
        "GEMFILES" => JSON.generate(["gemfiles/rails.gemfile"]),
      ) do
        expect { invoke("check_matrix_bundle") }.to raise_error("missing gems")
      end
    end
  end
end
