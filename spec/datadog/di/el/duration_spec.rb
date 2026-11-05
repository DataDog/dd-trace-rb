# frozen_string_literal: true

require "spec_helper"
require_relative "../spec_helper"
require "datadog/di/el"

RSpec.describe "DI EL @duration" do
  di_test

  let(:compiler) { Datadog::DI::EL::Compiler.new }

  let(:context) do
    Datadog::DI::Context.new(
      probe: nil, settings: nil, serializer: nil,
      duration: duration,
    )
  end

  # Deadline far enough in the future that a test evaluation stays within it.
  def far_future_deadline
    Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) + 60.0
  end

  def evaluate(ast)
    compiled, regexps = compiler.compile(ast)
    Datadog::DI::EL::Expression.new("(expression)", compiled, regexps: regexps).evaluate(context, evaluation_deadline: far_future_deadline)
  end

  context "at entry time, when duration is nil" do
    let(:duration) { nil }

    it "resolves @duration to nil instead of raising" do
      expect(evaluate("ref" => "@duration")).to be_nil
    end

    it "resolves isUndefined(@duration) to true instead of raising" do
      expect(evaluate("isUndefined" => {"ref" => "@duration"})).to be(true)
    end
  end

  context "at exit time, when duration is known" do
    let(:duration) { 0.5 }

    it "scales @duration to milliseconds" do
      expect(evaluate("ref" => "@duration")).to eq(500.0)
    end

    it "resolves isUndefined(@duration) to false" do
      expect(evaluate("isUndefined" => {"ref" => "@duration"})).to be(false)
    end
  end
end
