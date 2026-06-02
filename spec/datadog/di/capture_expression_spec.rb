require "datadog/di/spec_helper"
require "datadog/di/capture_expression"
require "datadog/di/probe"

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

RSpec.describe Datadog::DI::CaptureLimits do
  di_test

  describe ".new" do
    it "stores all four fields" do
      cl = described_class.new(
        max_reference_depth: 5,
        max_collection_size: 50,
        max_length: 100,
        max_field_count: 10,
      )
      expect(cl.max_reference_depth).to eq(5)
      expect(cl.max_collection_size).to eq(50)
      expect(cl.max_length).to eq(100)
      expect(cl.max_field_count).to eq(10)
    end

    it "defaults all four fields to nil" do
      cl = described_class.new
      expect(cl.max_reference_depth).to be_nil
      expect(cl.max_collection_size).to be_nil
      expect(cl.max_length).to be_nil
      expect(cl.max_field_count).to be_nil
    end
  end

  describe ".resolve" do
    let(:settings) do
      double("settings", dynamic_instrumentation: double(
        max_capture_depth: 3,
        max_capture_collection_size: 100,
        max_capture_string_length: 255,
        max_capture_attribute_count: 20,
      ))
    end
    let(:probe) do
      instance_double(Datadog::DI::Probe,
        max_capture_depth: nil,
        max_capture_attribute_count: nil,
        max_capture_collection_size: nil,
        max_capture_string_length: nil,)
    end

    context "no expression limits and no probe limits" do
      it "falls back to settings for all four fields" do
        resolved = described_class.resolve(expr_limits: nil, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 3, collection_size: 100, length: 255, attribute_count: 20)
      end
    end

    context "probe-level limits set" do
      let(:probe) do
        instance_double(Datadog::DI::Probe,
          max_capture_depth: 7,
          max_capture_attribute_count: 99,
          max_capture_collection_size: nil,
          max_capture_string_length: nil,)
      end

      it "uses probe limits for depth and attribute_count, settings for the rest" do
        resolved = described_class.resolve(expr_limits: nil, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 7, collection_size: 100, length: 255, attribute_count: 99)
      end
    end

    context "probe-level collection_size and length set" do
      let(:probe) do
        instance_double(Datadog::DI::Probe,
          max_capture_depth: nil,
          max_capture_attribute_count: nil,
          max_capture_collection_size: 33,
          max_capture_string_length: 77,)
      end

      it "uses probe-level overrides for collection_size and length" do
        resolved = described_class.resolve(expr_limits: nil, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 3, collection_size: 33, length: 77, attribute_count: 20)
      end
    end

    context "per-expression limits set on a subset of fields" do
      let(:expr_limits) do
        described_class.new(max_length: 50)
      end

      it "uses expression limit for the set field; probe / settings for the rest" do
        resolved = described_class.resolve(expr_limits: expr_limits, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 3, collection_size: 100, length: 50, attribute_count: 20)
      end
    end

    context "per-expression limits and probe limits both set" do
      let(:expr_limits) do
        described_class.new(max_reference_depth: 8)
      end
      let(:probe) do
        instance_double(Datadog::DI::Probe,
          max_capture_depth: 5,
          max_capture_attribute_count: 7,
          max_capture_collection_size: nil,
          max_capture_string_length: nil,)
      end

      it "expression wins over probe; probe wins over settings for the rest" do
        resolved = described_class.resolve(expr_limits: expr_limits, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 8, collection_size: 100, length: 255, attribute_count: 7)
      end
    end

    context "per-expression length set and probe-level collection_size set" do
      let(:expr_limits) do
        described_class.new(max_length: 20)
      end
      let(:probe) do
        instance_double(Datadog::DI::Probe,
          max_capture_depth: nil,
          max_capture_attribute_count: nil,
          max_capture_collection_size: 44,
          max_capture_string_length: 88,)
      end

      it "expression wins over probe for length; probe wins over settings for collection_size" do
        resolved = described_class.resolve(expr_limits: expr_limits, probe: probe, settings: settings)
        expect(resolved).to eq(depth: 3, collection_size: 44, length: 20, attribute_count: 20)
      end
    end
  end
end
