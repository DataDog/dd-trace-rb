# frozen_string_literal: true

require "spec_helper"
require_relative "../../.github/scripts/system_tests_selector"

RSpec.describe SystemTests::Selector do
  subject(:selection) { described_class.new(changed_files).call }

  context "with changes isolated to one product" do
    let(:changed_files) do
      [
        "lib/datadog/appsec/context.rb",
        "lib/datadog/appsec/processor.rb",
      ]
    end

    it "recommends that product's scenario group" do
      expect(selection.groups).to eq(["appsec"])
      expect(selection.full_suite).to be(false)
    end
  end

  context "with changes to multiple isolated products" do
    let(:changed_files) do
      [
        "lib/datadog/profiling/collectors/cpu_and_wall_time_worker.rb",
        "lib/datadog/tracing/sampling/rule_sampler.rb",
      ]
    end

    it "combines the product scenario groups" do
      expect(selection.groups).to eq(["profiling", "sampling"])
      expect(selection.full_suite).to be(false)
    end
  end

  context "with native profiling changes" do
    let(:changed_files) { ["ext/datadog_profiling_native_extension/collectors_cpu_and_wall_time_worker.c"] }

    it "recognizes the profiling product" do
      expect(selection.groups).to eq(["profiling"])
    end
  end

  context "with a shared change mixed with an isolated product" do
    let(:changed_files) do
      [
        "lib/datadog/appsec/context.rb",
        "lib/datadog/core/configuration/components.rb",
      ]
    end

    it "fails open to the full suite" do
      expect(selection.groups).to eq(["tracer_release"])
      expect(selection.full_suite).to be(true)
    end
  end

  context "without changed files" do
    let(:changed_files) { [] }

    it "fails open to the full suite" do
      expect(selection.groups).to eq(["tracer_release"])
      expect(selection.full_suite).to be(true)
    end
  end
end

RSpec.describe SystemTests::Report do
  it "explains that shadow mode does not alter test execution" do
    selection = SystemTests::Selector.new(["lib/datadog/open_feature/provider.rb"]).call

    report = described_class.new(selection).to_markdown

    expect(report).to include("does not change the system-tests executed")
    expect(report).to include("**Recommended scenario groups:** `ffe`")
    expect(report).to include("OpenFeature product code")
  end
end
