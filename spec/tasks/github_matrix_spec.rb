require "spec_helper"
require "tmpdir"
require_relative "../../tasks/github_matrix"

RSpec.describe GithubMatrix do
  subject(:matrix) do
    described_class.new(
      ruby_version: "4.0",
      gemfile_resolver: gemfile_resolver,
    )
  end

  let(:gemfile_resolver) do
    lambda do |group|
      raise "base" if group.empty?

      "gemfiles/ruby_4.0_#{group}.gemfile"
    end
  end

  let(:matrix_path) do
    path = File.join(temporary_directory, "Matrixfile")
    File.write(path, <<~RUBY)
      {
        "main" => {
          "" => "✅ 3.4 / ✅ 4.0",
          "rails" => "❌ 3.4 / ✅ 4.0",
          "old" => "✅ 3.4 / ❌ 4.0",
        },
        "mongodb" => {
          "mongo" => "✅ 4.0",
        },
      }
    RUBY
    path
  end

  around do |example|
    Dir.mktmpdir do |directory|
      @temporary_directory = directory
      Dir.chdir(directory) { example.run }
    end
  end

  before do
    allow(AppraisalConversion).to receive(:parent_gemfile).and_return("Gemfile")
  end

  let(:temporary_directory) { @temporary_directory }

  it "selects tasks compatible with the requested Ruby version" do
    expect(matrix.tasks).to eq(
      [
        {task: "main", group: "", gemfile: "Gemfile"},
        {task: "main", group: "rails", gemfile: "gemfiles/ruby_4.0_rails.gemfile"},
        {task: "mongodb", group: "mongo", gemfile: "gemfiles/ruby_4.0_mongo.gemfile"},
      ]
    )
  end

  it "separates tasks needing miscellaneous services" do
    expect(matrix.standard_tasks.map { |task| task[:task] }).to eq(["main", "main"])
    expect(matrix.misc_tasks.map { |task| task[:task] }).to eq(["mongodb"])
  end

  it "returns sorted unique applicable Gemfiles" do
    expect(matrix.gemfiles).to eq(
      [
        "Gemfile",
        "gemfiles/ruby_4.0_mongo.gemfile",
        "gemfiles/ruby_4.0_rails.gemfile",
      ]
    )
  end

  context "when a non-empty group has no appraisal Gemfile" do
    let(:gemfile_resolver) do
      lambda do |group|
        raise "missing appraisal" if group == "rails"

        "gemfiles/ruby_4.0_#{group}.gemfile"
      end
    end

    it "uses the fallback Gemfile" do
      rails_task = matrix.tasks.find { |task| task[:group] == "rails" }

      expect(rails_task).to include(gemfile: "Gemfile")
    end
  end

end
