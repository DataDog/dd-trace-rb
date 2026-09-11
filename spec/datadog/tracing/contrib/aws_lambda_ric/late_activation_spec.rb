# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/aws_lambda_ric/late_activation"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::LateActivation do
  let(:integration) { double("integration", patch: true) }

  before do
    allow(described_class::PATCH_ONCE).to receive(:run).and_yield
    allow(Datadog.configuration.tracing).to receive(:instrumented_integrations).and_return(test: integration)
  end

  it "patches integrations loaded by the handler file" do
    described_class.patch!

    expect(integration).to have_received(:patch)
  end

  it "re-evaluates AppSec auto-instrumentation when enabled" do
    stub_const(
      "Datadog::AppSec::Contrib::AutoInstrument",
      Module.new do
        def self.patch_all
        end
      end,
    )
    allow(Datadog::AppSec::Contrib::AutoInstrument).to receive(:patch_all)

    described_class.patch!

    expect(Datadog::AppSec::Contrib::AutoInstrument).to have_received(:patch_all)
  end
end
