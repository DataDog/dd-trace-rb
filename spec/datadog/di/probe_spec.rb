require "datadog/di/spec_helper"
require "datadog/di/probe"

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

      it "raises ArgumentError" do
        expect do
          probe
        end.to raise_error(ArgumentError, /both line number and method name/)
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
end
