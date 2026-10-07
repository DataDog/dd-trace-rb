require "spec_helper"
require "tmpdir"
require_relative "../../tasks/github_batching"

RSpec.describe GithubBatching do
  describe ".aggregate_timing_files" do
    it "uses the median build and test duration for each Ruby task" do
      Dir.mktmpdir do |directory|
        [10, 30, 20].each_with_index do |seconds, index|
          path = File.join(directory, "sample-#{index}.json")
          File.write(path, JSON.dump({
            "ruby_version" => "3.1",
            "tasks" => [{
              "task" => "main",
              "group" => "",
              "build_seconds" => 5,
              "test_seconds" => seconds,
            }],
          }))
        end

        aggregate = described_class.aggregate_timing_files(Dir[File.join(directory, "*.json")])

        expect(aggregate).to eq({
          "ruby_versions" => {
            "3.1" => [{"task" => "main", "group" => "", "seconds" => 25.0}],
          },
        })
      end
    end
  end

  describe ".distribute" do
    def task(name)
      {task: name, group: "", gemfile: "Gemfile"}
    end

    it "assigns the longest remaining task to the lightest batch" do
      tasks = %w[a b c d e f].map { |name| task(name) }
      estimates = %w[a b c d e f].zip([9, 8, 7, 6, 5, 4]).map { |name, seconds| [[name, ""], seconds] }.to_h

      batches = described_class.distribute(tasks, estimates, 2)

      expect(batches.map { |batch| batch[:tasks].map { |entry| entry[:task] } }).to eq([%w[a d e], %w[b c f]])
      expect(batches.map { |batch| batch[:seconds] }).to eq([20.0, 19.0])
    end

    it "breaks equal-duration ties by task name and batch number" do
      tasks = %w[d c b a].map { |name| task(name) }
      estimates = tasks.map { |entry| [[entry[:task], ""], 10] }.to_h

      batches = described_class.distribute(tasks, estimates, 2)

      expect(batches.map { |batch| batch[:tasks].map { |entry| entry[:task] } }).to eq([%w[a c], %w[b d]])
    end

    it "uses the upper quartile estimate for a task without history" do
      tasks = %w[a b c d new].map { |name| task(name) }
      estimates = %w[a b c d].zip([10, 20, 30, 40]).map { |name, seconds| [[name, ""], seconds] }.to_h

      batches = described_class.distribute(tasks, estimates, 1)

      expect(batches.first[:seconds]).to eq(140.0)
      expect(batches.first[:tasks].first[:task]).to eq("d")
      expect(batches.first[:tasks].map { |entry| entry[:task] }).to include("new")
    end
  end
end
