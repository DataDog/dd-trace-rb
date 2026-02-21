# typed: ignore

require 'spec_helper'

require 'datadog/tracing/traceable'

RSpec.describe Datadog::Tracing::Traceable do
  class TraceableClass
    include Datadog::Tracing::Traceable

    STRING_VALUE = "return value"

    def an_object
      OpenStruct.new something: "expected!", something_else: "unexpected"
    end

    def string_value
      STRING_VALUE
    end

    def method_returning_arg(first)
      first
    end

    protected
    def protected_string_value
      STRING_VALUE
    end

    private
    def private_string_value
      STRING_VALUE
    end
  end

  before do
    allow(Datadog::Tracing).to receive(:trace) do |*args, &block|
      tracer.trace(*args, &block)
    end

    allow(Datadog::Tracing).to receive(:tracer).and_return(tracer)
  end

  after { tracer.shutdown! }

  let(:tracer) { Datadog::Tracing::Tracer.new(writer: writer) }
  let(:writer) { FauxWriter.new }

  subject(:anonymous_traceable_class) do |example|
    TraceableClass.dup.class_eval do # dup the class so it's clean for every test
      define_singleton_method(:inspect) do
        "TraceableClass (for #{example.example_group})" # give the anonymous class an intelligible inspect value
      end

      def inspect
        "#<#{self.class.inspect}:#{super.split(":").last}" # give the instance an intelligible inspect value
      end

      self # Return the class as the subject
    end
  end

  shared_examples "non-existent method" do
    it "raises an ArgumentError referencing the method" do
      expect { subject }.to raise_error(ArgumentError, /a_nonexistent_method/)
    end

    it "raises an ArgumentError referencing the class missing the method" do
      expect { subject }.to raise_error(ArgumentError, /TraceableClass/)
    end
  end

  shared_examples "return value" do
    it "returns same object as the original method" do
      expect(subject.string_value).to be(TraceableClass::STRING_VALUE)
    end
  end

  shared_examples "method access" do
    context "when the method is protected" do
      it "raises a NoMethodError" do
        expect { subject.protected_string_value }.to raise_error(NoMethodError, /protected method/)
      end

      it "exists as a protected method" do
        expect(subject.protected_methods).to include(:protected_string_value)
      end
    end

    context "when the method is private" do
      it "raises a NoMethodError" do
        expect { subject.private_string_value }.to raise_error(NoMethodError, /private method/)
      end

      it "exists as a private method" do
        expect(subject.private_methods).to include(:private_string_value)
      end
    end
  end

  describe "prepended module" do
    subject do
      anonymous_traceable_class.class_eval do
        datadog_span_tag :string_value
      end

      anonymous_traceable_class.ancestors.first
    end

    it "has a helpful inspect value" do
      expect(subject.inspect).to match(/traceable=:datadog_span_tag/)
      expect(subject.inspect).to match(/method=:string_value/)
      expect(subject.inspect).to match(/Datadog::Tracing::Traceable/)
    end

    it "overrides the instance method specified" do
      expect(subject.instance_methods).to include(:string_value)
    end
  end

  describe "overridden method with arguments" do
    subject do
      anonymous_traceable_class.class_eval do
        datadog_span_tag :method_returning_arg
      end

      anonymous_traceable_class.new.method_returning_arg(arg)
    end

    let(:arg) { "an argument" }

    it "forwards the arguments to the original method" do
      is_expected.to be arg
    end
  end

  describe ".datadog_trace_method" do
    subject do
      anonymous_traceable_class.class_eval do
        datadog_trace_method :string_value, operation_name: "class.string_value"
        datadog_trace_method :protected_string_value, operation_name: "class.protected_string_value"
        datadog_trace_method :private_string_value, operation_name: "class.private_string_value"
      end

      anonymous_traceable_class.new
    end

    it "traces the named method when it is called" do
      subject.string_value

      expect(spans.first.name).to eq "class.string_value"
    end

    context "when the named method doesn't exist" do
      include_examples "non-existent method" do
        subject do
          anonymous_traceable_class.class_eval do
            datadog_trace_method :a_nonexistent_method, operation_name: "my.operation"
          end
        end
      end
    end

    include_examples "return value"
    include_examples "method access"
  end

  describe ".datadog_span_tag" do
    subject do
      anonymous_traceable_class.class_eval do
        datadog_span_tag :string_value
        datadog_span_tag :protected_string_value
        datadog_span_tag :private_string_value
      end

      anonymous_traceable_class.new
    end

    context "with a block" do
      subject! do
        anonymous_traceable_class.class_eval do
          datadog_span_tag :an_object do |object|
            object.something
          end
        end

        tracer.trace 'my_operation' do
          anonymous_traceable_class.new.an_object
        end
      end

      let(:traces) { tracer.writer.traces }
      let(:spans) { traces.first.spans }

      it "uses the return value of the block as the tag value" do
        expect(spans.first.meta).to include("an_object")
        expect(spans.first.meta["an_object"]).to eq "expected!"
      end
    end

    context "with a custom tag name" do
      subject do
        anonymous_traceable_class.class_eval do
          datadog_span_tag :string_value, tag_name:
        end
      end
    end

    context "when the named method doesn't exist" do
      include_examples "non-existent method" do
        subject do
          anonymous_traceable_class.class_eval do
            datadog_trace_method :a_nonexistent_method, operation_name: "my.operation"
          end
        end
      end
    end

    include_examples "return value"
    include_examples "method access"
  end
end
