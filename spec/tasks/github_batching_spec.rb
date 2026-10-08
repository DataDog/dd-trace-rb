require "spec_helper"
require "tmpdir"
require_relative "../../tasks/github_batching"

RSpec.describe GithubBatching do
  describe ".aggregate_timing_files" do
    it "separates task execution from Gemfile setup and reports p50 and p90" do
      Dir.mktmpdir do |directory|
        [[10, 4], [30, 8], [20, 6]].each_with_index do |(test_seconds, build_seconds), index|
          path = File.join(directory, "sample-#{index}.json")
          File.write(path, JSON.dump({
            "ruby_version" => "3.1",
            "tasks" => [
              {
                "task" => "main",
                "group" => "",
                "gemfile" => "/workspace/Gemfile",
                "build_seconds" => build_seconds,
                "test_seconds" => test_seconds,
              },
              {
                "task" => "contrib",
                "group" => "",
                "gemfile" => "/workspace/Gemfile",
                "build_seconds" => 1,
                "test_seconds" => 5,
              },
            ],
          }))
        end

        aggregate = described_class.aggregate_timing_files(Dir[File.join(directory, "*.json")])

        expect(aggregate).to eq({
          "ruby_versions" => {
            "3.1" => {
              "tasks" => [
                {"p50_seconds" => 5, "p90_seconds" => 5, "samples" => 3, "task" => "contrib", "group" => ""},
                {"p50_seconds" => 20, "p90_seconds" => 30, "samples" => 3, "task" => "main", "group" => ""},
              ],
              "gemfiles" => [
                {"p50_seconds" => 7, "p90_seconds" => 9, "samples" => 3, "gemfile" => "Gemfile"},
              ],
            },
          },
        })
      end
    end
  end

  describe ".timing_estimates" do
    def weights(ruby_version, main_seconds)
      {
        "ruby_versions" => {
          ruby_version => {
            "tasks" => [{"task" => "main", "group" => "", "p90_seconds" => main_seconds}],
            "gemfiles" => [{"gemfile" => "Gemfile", "p90_seconds" => 5}],
          },
        },
      }
    end

    it "uses the fetched remote weights" do
      allow(described_class).to receive(:fetch_weights).and_return(weights("3.1", 42))

      estimates = described_class.timing_estimates("3.1")

      expect(estimates[:tasks]).to eq(["main", ""] => 42)
    end

    it "returns empty estimates when the fetch fails so tasks use fallback durations" do
      allow(described_class).to receive(:fetch_weights).and_return(nil)

      estimates = described_class.timing_estimates("3.1")

      expect(estimates).to eq(tasks: {}, gemfiles: {})
    end
  end

  describe ".distribute" do
    def task(name, gemfile = "Gemfile")
      {task: name, group: "", gemfile: gemfile}
    end

    def estimates(task_seconds, gemfile_seconds = {"Gemfile" => 0})
      {
        tasks: task_seconds.map { |name, seconds| [[name, ""], seconds] }.to_h,
        gemfiles: gemfile_seconds,
      }
    end

    it "assigns the longest remaining Gemfile group to the lightest batch" do
      tasks = [task("a", "a.gemfile"), task("b", "b.gemfile"), task("c", "c.gemfile")]
      timing_estimates = estimates({"a" => 9, "b" => 8, "c" => 7}, {
        "a.gemfile" => 1,
        "b.gemfile" => 1,
        "c.gemfile" => 1,
      })

      batches = described_class.distribute(tasks, timing_estimates, 2)

      expect(batches.map { |batch| batch[:tasks].map { |entry| entry[:task] } }).to eq([%w[a], %w[b c]])
      expect(batches.map { |batch| batch[:seconds] }).to eq([10.0, 17.0])
    end

    it "keeps tasks with the same Gemfile together when splitting would be slower" do
      tasks = [task("a"), task("b"), task("c", "other.gemfile")]
      timing_estimates = estimates({"a" => 50, "b" => 50, "c" => 60}, {
        "Gemfile" => 10,
        "other.gemfile" => 10,
      })

      batches = described_class.distribute(tasks, timing_estimates, 2)

      expect(batches.map { |batch| batch[:tasks].map { |entry| entry[:task] } }).to eq([%w[a b], %w[c]])
      expect(batches.map { |batch| batch[:seconds] }).to eq([110.0, 70.0])
    end

    it "splits a Gemfile group when the extra setup lowers the slowest batch" do
      tasks = [task("a"), task("b"), task("c", "other.gemfile")]
      timing_estimates = estimates({"a" => 100, "b" => 100, "c" => 20}, {
        "Gemfile" => 10,
        "other.gemfile" => 10,
      })

      batches = described_class.distribute(tasks, timing_estimates, 2)

      expect(batches.map { |batch| batch[:tasks].map { |entry| entry[:task] } }).to eq([%w[b], %w[c a]])
      expect(batches.map { |batch| batch[:seconds] }).to eq([110.0, 140.0])
    end

    it "uses upper quartile fallbacks for tasks and Gemfiles without history" do
      tasks = [task("known", "known.gemfile"), task("new", "new.gemfile")]
      timing_estimates = estimates({"a" => 10, "b" => 20, "c" => 30, "known" => 40}, {
        "a.gemfile" => 1,
        "b.gemfile" => 2,
        "c.gemfile" => 3,
        "known.gemfile" => 4,
      })

      batches = described_class.distribute(tasks, timing_estimates, 1)

      expect(batches.first[:seconds]).to eq(88.0)
    end
  end
end
