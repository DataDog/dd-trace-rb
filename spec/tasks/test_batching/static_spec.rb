# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/static"
require_relative "../../../tasks/lib/test_batching/task_matrix"

RSpec.describe TestBatching::Static do
  def matrix
    {
      "main" => {"" => ["✅ 3.4"]},
      "contrib" => {"" => ["✅ 3.4"]},
      "mongodb" => {"" => ["✅ 3.4"]},
      "skipped" => {"" => ["✅ 3.3"]},
    }
  end

  it "even-splits the matching tasks and routes misc services out, with no estimates" do
    plan = described_class.new.plan(TestBatching::TaskMatrix.new(matrix), "3.4")

    expect(plan.misc_tasks.map(&:name)).to eq(["mongodb"])
    # Two matching tasks, one per batch: master's batching shape exactly.
    expect(plan.batches.map { |batch| batch.tasks.map(&:name) }).to eq([["main"], ["contrib"]])
    expect(plan.batches.map(&:seconds)).to eq([nil, nil])
  end

  it "emits master's matrix JSON" do
    data = described_class.new.plan(TestBatching::TaskMatrix.new(matrix), "3.4").to_matrix

    expect(data.keys).to eq(["batches", "misc"])
    expect(data["batches"]["include"].first.keys).to eq(["batch", "tasks"])
    expect(data["misc"]["include"].first["tasks"].first.to_h).to include("task" => "mongodb")
  end
end
