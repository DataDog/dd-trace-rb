require "spec_helper"

require "datadog/core/telemetry/event/app_endpoints_loaded"

RSpec.describe Datadog::Core::Telemetry::Event::AppEndpointsLoaded do
  subject(:event) { described_class.new(serialized_endpoints, is_first_event: false) }

  let(:serialized_endpoints) do
    [{
      type: "REST",
      resource_name: "GET /events",
      operation_name: "http.request",
      method: "GET",
      path: "/events"
    }]
  end

  it "returns app-endpoints for type" do
    expect(event.type).to eq("app-endpoints")
  end

  describe "#payload" do
    it "has endpoints attribute" do
      expect(event.payload.fetch(:endpoints)).to eq(serialized_endpoints)
    end

    it "has is_first attribute" do
      expect(event.payload.fetch(:is_first)).to eq(false)
    end
  end
end
