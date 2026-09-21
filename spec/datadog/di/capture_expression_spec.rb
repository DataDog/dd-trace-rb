require "datadog/di/spec_helper"
require "datadog/di/capture_expression"

RSpec.describe Datadog::DI::CaptureExpression do
  di_test

  describe ".new" do
    it "stores name, expr and limits" do
      ce = described_class.new(name: "x", expr: :compiled, limits: :limits)
      expect(ce.name).to eq("x")
      expect(ce.expr).to eq(:compiled)
      expect(ce.limits).to eq(:limits)
    end

    it "defaults limits to nil" do
      ce = described_class.new(name: "x", expr: :compiled)
      expect(ce.limits).to be_nil
    end
  end
end
