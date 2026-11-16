# frozen_string_literal: true

require "datadog/appsec/native_output_helpers"
require "datadog/appsec/monitor/gateway/watcher"

RSpec.describe Datadog::AppSec::Monitor::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  before do
    described_class.watch_user_id(gateway)
    described_class.watch_user_login(gateway)
    allow(Datadog::AppSec).to receive(:active_context).and_return(context)
  end

  context "identity" do
    let(:output_address) { "usr.id" }
    subject(:consume) do
      gateway.push("identity.set_user", double(id: "123", login: nil, session_id: nil))
    end
    it_behaves_like "a native AppSec output consumer", :on_record
  end

  %w[users.login.success users.login.failure].each do |event|
    context event do
      let(:output_address) { "server.business_logic.#{event}" }
      subject(:consume) { gateway.push("appsec.events.user_lifecycle", event) }
      it_behaves_like "a native AppSec output consumer", :on_record
    end
  end
end
