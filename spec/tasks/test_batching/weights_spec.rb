# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/weights"

RSpec.describe TestBatching::Weights do
  def task(name, gemfile: "gemfiles/foo.gemfile")
    TestBatching::Task.new(name: name, group: "", gemfile: gemfile)
  end

  it "separates task execution from Gemfile setup and reports p50 and p90" do
    # Three runs of one batch: main and contrib share the parent Gemfile.
    runs = [[10, 4], [30, 8], [20, 6]].map do |main_test, main_build|
      TestBatching::BatchTiming.new(
        ruby_version: "3.1",
        timings: [
          TestBatching::TaskTiming.new(task: task("main"), build_seconds: main_build, test_seconds: main_test),
          TestBatching::TaskTiming.new(task: task("contrib"), build_seconds: 1, test_seconds: 5),
        ]
      )
    end

    weights = described_class.from(runs)

    expect(weights.to_h).to eq({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [
            {"p50_seconds" => 5, "p90_seconds" => 5, "samples" => 3, "task" => "contrib", "group" => ""},
            {"p50_seconds" => 20, "p90_seconds" => 30, "samples" => 3, "task" => "main", "group" => ""},
          ],
          "gemfiles" => [
            {"p50_seconds" => 7, "p90_seconds" => 9, "samples" => 3, "gemfile" => "foo.gemfile"},
          ],
        },
      },
    })
  end

  it "answers costs per Ruby, falling back for tasks without history" do
    weights = described_class.new({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [{"task" => "main", "group" => "", "p90_seconds" => 42}],
          "gemfiles" => [{"gemfile" => "Gemfile", "p90_seconds" => 5}],
        },
      },
    })

    ruby = weights.for_ruby("3.1")
    expect(ruby.test_cost(task("main"))).to eq(42)
    expect(ruby.setup_cost("Gemfile")).to eq(5)

    # A task and Gemfile without history fall back to the upper quartile.
    expect(ruby.test_cost(task("unknown"))).to eq(42)
    expect(ruby.setup_cost("unknown.gemfile")).to eq(5)
  end

  it "falls back to a minute for a Ruby it has never seen" do
    weights = described_class.new({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [{"task" => "main", "group" => "", "p90_seconds" => 42}],
          "gemfiles" => [{"gemfile" => "Gemfile", "p90_seconds" => 5}],
        },
      },
    })

    other_ruby = weights.for_ruby("3.2")

    expect(other_ruby.test_cost(task("main"))).to eq(60.0)
    expect(other_ruby.setup_cost("Gemfile")).to eq(60.0)
  end

  it "knows when it carries no weights at all" do
    expect(described_class.new({}).empty?).to be(true)
    expect(described_class::Missing.new.empty?).to be(true)
    expect(described_class::Missing.new).to be_a(described_class)
  end
end
