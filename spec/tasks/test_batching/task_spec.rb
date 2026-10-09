# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/task"

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
