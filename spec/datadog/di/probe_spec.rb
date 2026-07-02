require "datadog/di/spec_helper"
require "datadog/di/probe"
require "datadog/di/capture_expression"
require "datadog/di/el"

RSpec.describe Datadog::DI::Probe do
  di_test

  shared_context "method probe" do
    let(:probe) do
      described_class.new(id: "42", type: :log, type_name: 'Foo', method_name: "bar")
    end
  end

  shared_context "line probe" do
    let(:probe) do
      described_class.new(id: "42", type: :log, file: "foo.rb", line_no: 4)
    end
  end

  describe ".new" do
    context "method probe" do
      include_context "method probe"

      it "creates an instance" do
        expect(probe).to be_a(described_class)
        expect(probe.id).to eq "42"
        expect(probe.type).to eq :log
        expect(probe.type_name).to eq "Foo"
        expect(probe.method_name).to eq "bar"
        expect(probe.file).to be nil
        expect(probe.line_no).to be nil
      end
    end

    context "line probe" do
      include_context "line probe"

      it "creates an instance" do
        expect(probe).to be_a(described_class)
        expect(probe.id).to eq "42"
        expect(probe.type).to eq :log
        expect(probe.type_name).to be nil
        expect(probe.method_name).to be nil
        expect(probe.file).to eq "foo.rb"
        expect(probe.line_no).to eq 4
      end
    end

    context 'line number given but file is not' do
      let(:probe) do
        described_class.new(id: "42", type: :log, line_no: 5)
      end

      it "raises ArgumentError" do
        expect do
          probe
        end.to raise_error(ArgumentError, /Probe contains line number but not file/)
      end
    end

    context 'unsupported type' do
      let(:probe) do
        # LOG_PROBE is a valid type in RC probe specification but not
        # as an argument to Probe constructor.
        described_class.new(id: '42', type: 'LOG_PROBE', file: 'x', line_no: 1)
      end

      it 'raises ArgumentError' do
        expect do
          probe
        end.to raise_error(ArgumentError, /Unknown probe type/)
      end
    end

    context "neither method nor line" do
      let(:probe) do
        described_class.new(id: "42", type: :log)
      end

      it "raises ArgumentError" do
        expect do
          probe
        end.to raise_error(ArgumentError, /neither method nor line/)
      end
    end

    context "both method and line" do
      let(:probe) do
        described_class.new(id: "42", type: :log,
          type_name: "foo", method_name: "bar", file: "baz", line_no: 4)
      end

      it "creates a line probe" do
        expect(probe.line?).to be true
        expect(probe.method?).to be false
      end
    end
  end

  describe "#line?" do
    context "line probe" do
      let(:probe) do
        described_class.new(id: "42", type: :log, file: "bar.rb", line_no: 5)
      end

      it "is true" do
        expect(probe.line?).to be true
      end
    end

    context "method probe" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "FooClass", method_name: "bar")
      end

      it "is false" do
        expect(probe.line?).to be false
      end
    end

    context "method probe with file name" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "FooClass", method_name: "bar", file: "quux.rb")
      end

      it "is false" do
        expect(probe.line?).to be false
      end
    end
  end

  describe "#method?" do
    context "line probe" do
      let(:probe) do
        described_class.new(id: "42", type: :log, file: "bar.rb", line_no: 5)
      end

      it "is false" do
        expect(probe.method?).to be false
      end
    end

    context "method probe" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "FooClass", method_name: "bar")
      end

      it "is true" do
        expect(probe.method?).to be true
      end
    end

    context "method probe with file name" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "FooClass", method_name: "bar", file: "quux.rb")
      end

      it "is true" do
        expect(probe.method?).to be true
      end
    end
  end

  describe "#line_no" do
    context "one line number" do
      let(:probe) { described_class.new(id: "x", type: :log, file: 'x', line_no: 5) }

      it "returns the line number" do
        expect(probe.line_no).to eq 5
      end
    end

    context "nil line number" do
      let(:probe) { described_class.new(id: "id", type: :log, type_name: "x", method_name: "y", line_no: nil) }

      it "returns nil" do
        expect(probe.line_no).to be nil
      end
    end
  end

  describe "#line_no!" do
    context "one line number" do
      let(:probe) { described_class.new(id: "x", type: :log, file: 'x', line_no: 5) }

      it "returns the line number" do
        expect(probe.line_no!).to eq 5
      end
    end

    context "nil line number" do
      let(:probe) { described_class.new(id: "id", type: :log, type_name: "x", method_name: "y", line_no: nil) }

      it "raises MissingLineNumber" do
        expect do
          probe.line_no!
        end.to raise_error(Datadog::DI::Error::MissingLineNumber, /does not have a line number/)
      end
    end
  end

  describe "capture expressions" do
    let(:capture_expression) do
      Datadog::DI::CaptureExpression.new(name: "x", expr: instance_double(Datadog::DI::EL::Expression))
    end

    context "no capture_expressions argument" do
      include_context "method probe"

      it "defaults to an empty array and capture_expressions? is false" do
        expect(probe.capture_expressions).to eq([])
        expect(probe.capture_expressions?).to be false
      end
    end

    context "capture_expressions provided" do
      let(:probe) do
        described_class.new(
          id: "42", type: :log, type_name: "Foo", method_name: "bar",
          capture_expressions: [capture_expression],
        )
      end

      it "stores them and capture_expressions? is true" do
        expect(probe.capture_expressions).to eq([capture_expression])
        expect(probe.capture_expressions?).to be true
      end

      it "defaults rate_limit to 1/sec (snapshot-class) when only capture_expressions set" do
        expect(probe.rate_limit).to eq(1)
      end
    end

    context "capture_expressions explicitly empty array, capture_snapshot false" do
      let(:probe) do
        described_class.new(
          id: "42", type: :log, type_name: "Foo", method_name: "bar",
          capture_expressions: [],
        )
      end

      it "defaults rate_limit to 5000/sec (log-class)" do
        expect(probe.rate_limit).to eq(5000)
      end
    end

    context "explicit rate_limit overrides the capture-expressions default" do
      let(:probe) do
        described_class.new(
          id: "42", type: :log, type_name: "Foo", method_name: "bar",
          capture_expressions: [capture_expression],
          rate_limit: 42,
        )
      end

      it "uses the explicit value" do
        expect(probe.rate_limit).to eq(42)
      end
    end
  end

  describe "evaluate_at" do
    context "omitted" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar")
      end

      it "defaults to :exit" do
        expect(probe.evaluate_at).to eq(:exit)
      end
    end

    context "explicitly nil" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
          evaluate_at: nil)
      end

      it "coerces to :exit" do
        expect(probe.evaluate_at).to eq(:exit)
      end
    end

    context ":entry" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
          evaluate_at: :entry)
      end

      it "is stored as :entry" do
        expect(probe.evaluate_at).to eq(:entry)
      end
    end

    context ":exit" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
          evaluate_at: :exit)
      end

      it "is stored as :exit" do
        expect(probe.evaluate_at).to eq(:exit)
      end
    end

    context "unknown symbol" do
      it "raises ArgumentError" do
        expect do
          described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
            evaluate_at: :before)
        end.to raise_error(ArgumentError, /Unknown evaluate_at value/)
      end
    end

    context "unknown String value" do
      it "raises ArgumentError" do
        expect do
          described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
            evaluate_at: "ENTRY")
        end.to raise_error(ArgumentError, /Unknown evaluate_at value/)
      end
    end
  end

  describe "#method_name!" do
    context "method name set" do
      let(:probe) { described_class.new(id: "x", type: :log, type_name: "Foo", method_name: "bar") }

      it "returns the method name" do
        expect(probe.method_name!).to eq "bar"
      end
    end

    context "nil method name" do
      let(:probe) { described_class.new(id: "id", type: :log, file: "x", line_no: 5, method_name: nil) }

      it "raises MissingMethodName" do
        expect do
          probe.method_name!
        end.to raise_error(Datadog::DI::Error::MissingMethodName, /does not have a method name/)
      end
    end
  end

  describe "#location" do
    context "method probe" do
      include_context "method probe"

      it "returns method location" do
        expect(probe.location).to eq "Foo.bar"
      end
    end

    context "line probe" do
      include_context "line probe"

      it "returns line location" do
        expect(probe.location).to eq "foo.rb:4"
      end
    end
  end

  describe "#snapshot_serializer_limits" do
    let(:settings) do
      double("settings", dynamic_instrumentation: double(
        max_capture_depth: 3,
        max_capture_attribute_count: 20,
        max_capture_string_length: 255,
        max_capture_collection_size: 100,
      ))
    end

    context "no probe-level overrides" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar")
      end

      it "returns all four settings defaults" do
        expect(probe.snapshot_serializer_limits(settings)).to eq(
          depth: 3,
          attribute_count: 20,
          length: 255,
          collection_size: 100,
        )
      end
    end

    context "all four probe-level overrides set" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
          max_capture_depth: 7,
          max_capture_attribute_count: 99,
          max_capture_string_length: 77,
          max_capture_collection_size: 33,)
      end

      it "returns the probe-level values for all four fields" do
        expect(probe.snapshot_serializer_limits(settings)).to eq(
          depth: 7,
          attribute_count: 99,
          length: 77,
          collection_size: 33,
        )
      end
    end

    context "mixed probe-level overrides" do
      let(:probe) do
        described_class.new(id: "42", type: :log, type_name: "Foo", method_name: "bar",
          max_capture_string_length: 50,)
      end

      it "uses the probe-level value where set, settings default otherwise" do
        expect(probe.snapshot_serializer_limits(settings)).to eq(
          depth: 3,
          attribute_count: 20,
          length: 50,
          collection_size: 100,
        )
      end
    end
  end
end
