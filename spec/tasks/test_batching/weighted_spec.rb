# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/weights"
require_relative "../../../tasks/lib/test_batching/weighted"

RSpec.describe TestBatching::Weighted do
  before do
    allow(AppraisalConversion).to receive(:to_bundle_gemfile) { |group| "gemfiles/#{group}.gemfile" }
    allow(AppraisalConversion).to receive(:parent_gemfile) { "gemfiles/Gemfile" }
  end

  def weights(task_seconds, gemfile_seconds)
    TestBatching::Weights::Ruby.new({
      "tasks" => task_seconds.map { |(name, group), seconds| {"task" => name, "group" => group, "p90_seconds" => seconds} },
      "gemfiles" => gemfile_seconds.map { |gemfile, seconds| {"gemfile" => gemfile, "p90_seconds" => seconds} },
    })
  end

  # tasks: [[name, group], ...] -- the group decides the Gemfile, as in the
  # real Matrixfile.
  def plan(tasks, weights, batch_count: 2)
    matrix = tasks.each_with_object({}) do |(name, group), hash|
      (hash[name] ||= {})[group] = ["✅ 3.4"]
    end

    described_class.new(weights, batch_count: batch_count).plan(TestBatching::TaskMatrix.new(matrix), "3.4")
  end

  it "assigns the longest remaining Gemfile group to the lightest batch" do
    tasks = [["a", "a"], ["b", "b"], ["c", "c"]]
    ruby_weights = weights(
      {["a", "a"] => 9, ["b", "b"] => 8, ["c", "c"] => 7},
      {"a.gemfile" => 1, "b.gemfile" => 1, "c.gemfile" => 1}
    )

    batches = plan(tasks, ruby_weights).batches

    expect(batches.map { |batch| batch.tasks.map(&:name) }).to eq([%w[a], %w[b c]])
    expect(batches.map(&:seconds)).to eq([10.0, 17.0])
  end

  it "keeps tasks with the same Gemfile together when splitting would be slower" do
    tasks = [["a", ""], ["b", ""], ["c", "other"]]
    ruby_weights = weights(
      {["a", ""] => 50, ["b", ""] => 50, ["c", "other"] => 60},
      {"Gemfile" => 10, "other.gemfile" => 10}
    )

    batches = plan(tasks, ruby_weights).batches

    expect(batches.map { |batch| batch.tasks.map(&:name) }).to eq([%w[a b], %w[c]])
    expect(batches.map(&:seconds)).to eq([110.0, 70.0])
  end

  it "splits a Gemfile group when the extra setup lowers the slowest batch" do
    tasks = [["a", ""], ["b", ""], ["c", "other"]]
    ruby_weights = weights(
      {["a", ""] => 100, ["b", ""] => 100, ["c", "other"] => 20},
      {"Gemfile" => 10, "other.gemfile" => 10}
    )

    batches = plan(tasks, ruby_weights).batches

    expect(batches.map { |batch| batch.tasks.map(&:name) }).to eq([%w[b], %w[c a]])
    expect(batches.map(&:seconds)).to eq([110.0, 140.0])
  end

  it "uses upper quartile fallbacks for tasks and Gemfiles without history" do
    tasks = [["known", "known"], ["new", "new"]]
    ruby_weights = weights(
      {["a", ""] => 10, ["b", ""] => 20, ["c", ""] => 30, ["known", "known"] => 40},
      {"a.gemfile" => 1, "b.gemfile" => 2, "c.gemfile" => 3, "known.gemfile" => 4}
    )

    batches = plan(tasks, ruby_weights, batch_count: 1).batches

    expect(batches.first.seconds).to eq(88.0)
  end

  it "emits the batched matrix JSON with estimated seconds and misc services out" do
    matrix = {
      "main" => {"" => ["✅ 3.4"]},
      "mongodb" => {"" => ["✅ 3.4"]},
    }

    data = described_class.new(weights({}, {})).plan(TestBatching::TaskMatrix.new(matrix), "3.4").to_matrix

    expect(data["misc"]["include"].first["tasks"].first["task"]).to eq("mongodb")
    expect(data["batches"]["include"].length).to eq(described_class::BATCH_COUNT)
    expect(data["batches"]["include"].first["tasks"].first["task"]).to eq("main")
    expect(data["batches"]["include"].first["estimated_seconds"]).to eq(120.0)
  end
end
