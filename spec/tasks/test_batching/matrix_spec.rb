# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/matrix"

RSpec.describe TestBatching::Task do
  it "equals tasks with the same name and group, whatever their Gemfile" do
    task = described_class.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile")
    same_task = described_class.new(name: "main", group: "", gemfile: "gemfiles/other.gemfile")
    other_group = described_class.new(name: "main", group: "rails8", gemfile: "gemfiles/foo.gemfile")

    expect(task).to eq(same_task)
    expect(task).not_to eq(other_group)
  end

  it "serializes to and from the matrix JSON shape" do
    task = described_class.new(name: "main", group: "rails8", gemfile: "gemfiles/foo.gemfile")

    expect(described_class.from_h(task.to_h)).to eq(task)
  end

  it "knows its Gemfile's name" do
    task = described_class.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile")

    expect(task.gemfile_name).to eq("foo.gemfile")
  end
end

RSpec.describe TestBatching::TaskMatrix do
  before do
    allow(AppraisalConversion).to receive(:to_bundle_gemfile) do |group|
      raise "Gemfile not found" if group.to_s.empty?

      "gemfiles/#{group}.gemfile"
    end
    allow(AppraisalConversion).to receive(:to_bundle_gemfile).with("missing") { raise "Gemfile not found" }
    allow(AppraisalConversion).to receive(:parent_gemfile) { "gemfiles/Gemfile" }
  end

  def matrix
    {
      "main" => {"" => ["✅ 3.4", "✅ 3.5"]},
      "core_with_rails" => {"rails8" => ["✅ 3.4"]},
      "legacy" => {"missing" => ["✅ 3.4"]},
      "mongodb" => {"" => ["✅ 3.4"]},
      "skipped" => {"" => ["✅ 3.3"]},
    }
  end

  it "collects the batchable tasks under a Ruby, mapped to their group Gemfiles" do
    tasks = described_class.new(matrix).batchable_tasks("3.4")

    expect(tasks.map(&:name)).to eq(["main", "core_with_rails", "legacy"])
    expect(tasks.map(&:gemfile)).to eq(
      ["gemfiles/Gemfile", "gemfiles/rails8.gemfile", "gemfiles/Gemfile"]
    )
  end

  it "splits service-dependent misc tasks from the batchable ones" do
    task_matrix = described_class.new(matrix)

    expect(task_matrix.misc_tasks("3.4").map(&:name)).to eq(["mongodb"])
    expect(task_matrix.misc_tasks("3.4").map(&:gemfile)).to eq(["gemfiles/Gemfile"])
  end
end
