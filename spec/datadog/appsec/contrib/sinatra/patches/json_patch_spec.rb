# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/sinatra/patches/json_patch"
require "sinatra/base"
require "sinatra/json"
require "rack/mock"

RSpec.describe Datadog::AppSec::Contrib::Sinatra::Patches::JsonPatch do
  describe "#json" do
    subject(:response) do
      Rack::MockRequest.new(app).get("/", Datadog::AppSec::Ext::CONTEXT_KEY => context)
    end

    before do
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      allow(gateway).to receive(:push).and_call_original
    end

    let(:app) do
      Class.new(Sinatra::Base).tap do |application|
        application.helpers(Sinatra::JSON)
        application.prepend(described_class) unless application < described_class
        application.set(:environment, :test)
        application.set(:show_exceptions, false)
        application.set(:raise_errors, true)
        application.set(:host_authorization, permitted_hosts: [])
        application.set(:response_payload, serializer)
        application.get("/") { json(settings.response_payload) }
      end
    end
    let(:context) { instance_double(Datadog::AppSec::Context) }
    let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
    let(:serializer) do
      Class.new do
        attr_reader :calls

        def initialize
          @calls = 0
        end

        def as_json
          @calls += 1
          {"x" => @calls}
        end

        def to_json(*_arguments)
          JSON.generate(as_json)
        end
      end.new
    end

    it "serializes the response object once" do
      expect { response }.to change(serializer, :calls).from(0).to(1)
    end

    it "preserves the first serialization result" do
      expect(response.body).to eq('{"x":1}')
    end

    it "passes the encoded response to the gateway without parsing JSON" do
      expect(JSON).not_to receive(:parse)

      response

      expect(gateway).to have_received(:push).with(
        "sinatra.response.body.json",
        have_attributes(data: '{"x":1}', context: context),
      )
    end

    context "when there is no AppSec context" do
      subject(:response) { Rack::MockRequest.new(app).get("/") }

      it "leaves serialization to Sinatra" do
        expect(response.body).to eq('{"x":1}')
        expect(serializer.calls).to eq(1)
        expect(gateway).not_to have_received(:push).with("sinatra.response.body.json", anything)
      end
    end

    context "when a custom encoder returns a Rack response" do
      before { app.set(:json_encoder, encoder) }

      let(:encoder) do
        Class.new do
          def self.encode(_object, _options = {})
            [200, {}, ["streamed JSON"]]
          end
        end
      end

      it "preserves the response without inspecting a non-string result" do
        expect(response.body).to eq("streamed JSON")
        expect(serializer.calls).to eq(0)
        expect(gateway).not_to have_received(:push).with("sinatra.response.body.json", anything)
      end
    end

    context "when AppSec blocks the response" do
      before do
        gateway.watch("sinatra.response.body.json") do |_stack, _container|
          throw Datadog::AppSec::Ext::INTERRUPT, :blocked
        end
      end

      it "propagates blocking after one serialization" do
        expect(catch(Datadog::AppSec::Ext::INTERRUPT) { response }).to eq(:blocked)
        expect(serializer.calls).to eq(1)
      end
    end
  end
end
