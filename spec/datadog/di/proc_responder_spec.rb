require "datadog/di/spec_helper"
require "datadog/di/proc_responder"
require "datadog/di/el/expression"

RSpec.describe Datadog::DI::ProcResponder do
  describe "#probe_expression_evaluation_failed_callback" do
    let(:condition) do
      Datadog::DI::EL::Expression.new("(expression)", "undefined_function()")
    end

    it "invokes the failed proc with the context and exception when called with the three-argument contract" do
      observed_args = []
      failed_proc = proc { |context, exc| observed_args << [context, exc] }
      responder = described_class.new(proc {}, failed_proc)

      context = double("context")
      exc = RuntimeError.new("boom")
      responder.probe_expression_evaluation_failed_callback(context, condition, exc)

      expect(observed_args).to eq [[context, exc]]
    end

    it "raises NotImplementedError when no failed proc is provided" do
      responder = described_class.new(proc {})

      expect do
        responder.probe_expression_evaluation_failed_callback(double("context"), condition, RuntimeError.new("boom"))
      end.to raise_error(NotImplementedError, "Failed proc not provided")
    end
  end

  describe "#probe_metric_emitted_callback" do
    it "invokes the emitted proc with the probe" do
      observed_probes = []
      emitted_proc = proc { |probe| observed_probes << probe }
      responder = described_class.new(proc {}, nil, emitted_proc)

      probe = double("probe")
      responder.probe_metric_emitted_callback(probe)

      expect(observed_probes).to eq [probe]
    end

    it "raises NotImplementedError when no emitted proc is provided" do
      responder = described_class.new(proc {})

      expect do
        responder.probe_metric_emitted_callback(double("probe"))
      end.to raise_error(NotImplementedError, "Emitted proc not provided")
    end
  end
end
