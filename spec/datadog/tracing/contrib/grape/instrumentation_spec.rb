require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/grape/instrumentation"
require "grape"

RSpec.describe Datadog::Tracing::Contrib::Grape::Instrumentation::ExecutePatch do
  # Grape 4.1 moved the per-endpoint state (including the endpoint block) into a
  # state object, so the `@source` instance variable is never set. The block is
  # only reachable through the public `#source` reader, which this stub mirrors.
  let(:endpoint_class) do
    Class.new do
      def initialize(source)
        @state = Struct.new(:source).new(source)
      end

      def source
        @state.source
      end

      def execute(*args)
        [:executed, args]
      end
    end.tap { |klass| klass.prepend(described_class) }
  end

  let(:endpoint) { endpoint_class.new(source) }

  describe "#execute" do
    subject(:execute) { endpoint.execute(:arg) }

    context "when the endpoint has a block" do
      let(:source) { proc { "OK" } }

      it "runs the endpoint" do
        expect(execute).to eq([:executed, [:arg]])
      end
    end

    context "when the endpoint has no block" do
      let(:source) { nil }

      it "does not run the endpoint" do
        expect(execute).to be_nil
      end
    end
  end
end
