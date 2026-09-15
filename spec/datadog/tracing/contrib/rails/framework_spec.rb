# frozen_string_literal: true

require "spec_helper"
require "datadog/tracing/contrib/rails/framework"

RSpec.describe Datadog::Tracing::Contrib::Rails::Framework do
  describe ".activate_active_storage!" do
    subject(:activate_active_storage!) { described_class.activate_active_storage!(datadog_config, rails_config) }

    let(:tracing) { double("tracing configuration") }
    let(:datadog_config) { double("datadog configuration", tracing: tracing) }
    let(:rails_config) { {} }

    context "when ActiveStorage is defined" do
      before { stub_const("ActiveStorage", Module.new) }

      it "instruments active_storage" do
        expect(tracing).to receive(:instrument).with(:active_storage)
        activate_active_storage!
      end
    end

    context "when ActiveStorage is not defined" do
      before { hide_const("ActiveStorage") }

      it "does not instrument active_storage" do
        expect(tracing).not_to receive(:instrument)
        expect(activate_active_storage!).to be_nil
      end
    end
  end
end
