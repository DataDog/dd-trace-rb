require "datadog/tracing/contrib/rails/configuration/settings"

RSpec.describe Datadog::Tracing::Contrib::Rails::Configuration::Settings do
  describe "#distributed_tracing" do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context "when default" do
      it { is_expected.to be true }
    end

    context "when configured via environment variable" do
      around do |example|
        ClimateControl.modify("DD_TRACE_RAILS_DISTRIBUTED_TRACING" => "false") do
          example.run
        end
      end

      it { is_expected.to be false }
    end
  end

  describe "#web_service_name" do
    subject(:web_service_name) { settings.web_service_name }

    context "when default" do
      let(:settings) { described_class.new }

      it { is_expected.to eq "web-server" }
    end

    context "when configured" do
      let(:settings) { described_class.new(web_service_name: "nginx") }

      it { is_expected.to eq "nginx" }
    end
  end
end
