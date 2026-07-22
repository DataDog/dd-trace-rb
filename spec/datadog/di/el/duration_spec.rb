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

  def evaluate(ast)
    Datadog::DI::EL::Expression.new("(expression)", *compiler.compile(ast)).evaluate(context)
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
