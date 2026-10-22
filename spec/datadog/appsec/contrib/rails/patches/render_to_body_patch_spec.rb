# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/rails/gateway/watcher"
require "datadog/appsec/contrib/rails/patches/render_to_body_patch"
require "action_controller"
require "libddwaf"

RSpec.describe Datadog::AppSec::Contrib::Rails::Patches::RenderToBodyPatch, execute_in_fork: true do
  describe "#render_to_body" do
    subject(:render_to_body) { controller.render_to_body(json: serializer) }

    before do
      controller.request = ActionDispatch::Request.new(Datadog::AppSec::Ext::CONTEXT_KEY => context)
      if controller.respond_to?(:set_response!)
        controller.set_response!(ActionDispatch::Response.new)
      else
        controller.response = ActionDispatch::Response.new
      end
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      allow(gateway).to receive(:push).and_call_original
    end

    let(:controller) { controller_class.new }
    let(:controller_class) do
      stub_const("JsonController", Class.new(ActionController::Base)).tap do |controller|
        controller.prepend(described_class) unless controller < described_class
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

        def as_json(*_arguments)
          @calls += 1
          {x: @calls}
        end
      end.new
    end

    it "serializes the response object once" do
      expect { render_to_body }.to change(serializer, :calls).from(0).to(1)
    end

    it "passes the rendered response without parsing JSON in Ruby" do
      expect(JSON).not_to receive(:parse)

      expect(render_to_body).to eq('{"x":1}')
    end

    it "preserves the response produced by the first serialization" do
      expect(JSON.parse(render_to_body)).to eq("x" => 1)
    end

    it "sends the rendered JSON representation to AppSec" do
      render_to_body

      expect(gateway).to have_received(:push).with(
        "rails.response.body.json",
        have_attributes(data: '{"x":1}', context: context),
      )
    end

    context "when there is no AppSec context" do
      before { controller.request.env.delete(Datadog::AppSec::Ext::CONTEXT_KEY) }

      it "leaves serialization to Rails" do
        expect(JSON.parse(render_to_body)).to eq("x" => 1)
        expect(gateway).not_to have_received(:push)
      end
    end

    context "when rendering plain text" do
      subject(:render_to_body) { controller.render_to_body(plain: "OK") }

      it "returns the response without JSON inspection" do
        expect(render_to_body).to eq("OK")
        expect(gateway).not_to have_received(:push)
      end
    end

    context "when the serializer is nested in a hash" do
      subject(:render_to_body) { controller.render_to_body(json: {item: serializer}) }

      it "serializes nested objects once" do
        expect(JSON.parse(render_to_body)).to eq("item" => {"x" => 1})
        expect(serializer.calls).to eq(1)
      end
    end

    context "when rendering an array" do
      subject(:render_to_body) { controller.render_to_body(json: [serializer]) }

      it "inspects the array without serializing its elements twice" do
        expect(JSON.parse(render_to_body)).to eq([{"x" => 1}])
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: '[{"x":1}]'),
        )
      end
    end

    context "when rendering with serialization options" do
      subject(:render_to_body) { controller.render_to_body(json: {visible: 1, hidden: 2}, only: [:visible]) }

      it "inspects only the fields included in the rendered response" do
        expect(JSON.parse(render_to_body)).to eq("visible" => 1)
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: '{"visible":1}'),
        )
      end
    end

    context "when the object defines custom JSON serialization" do
      let(:serializer) do
        Class.new do
          def as_json(*_arguments)
            raise "as_json must not be called"
          end

          def to_json(*_arguments)
            '{"custom":true}'
          end
        end.new
      end

      it "uses the custom JSON representation" do
        expect(render_to_body).to eq('{"custom":true}')
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: '{"custom":true}'),
        )
      end
    end

    context "when the response is already encoded JSON" do
      subject(:render_to_body) { controller.render_to_body(json: '{"x":1}') }

      it "passes the encoded response unchanged" do
        expect(render_to_body).to eq('{"x":1}')
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: '{"x":1}'),
        )
      end
    end

    context "when the JSON response is nested beyond 100 levels" do
      subject(:render_to_body) { controller.render_to_body(json: response_body) }

      let(:response_body) do
        JSON.generate(
          {"shallow" => "keep", "deep" => 120.times.inject(0) { |nested, _index| [nested] }},
          max_nesting: false,
        )
      end

      it "passes deeply nested JSON unchanged" do
        expect(render_to_body).to equal(response_body)
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: equal(response_body)),
        )
      end

      context "when the response is inspected by the WAF" do
        before do
          Datadog::AppSec::Contrib::Rails::Gateway::Watcher.watch_response_body_json(gateway)
        end

        after { context.finalize! }

        let(:context) do
          Datadog::AppSec::Context.new(
            Datadog::Tracing::TraceOperation.new,
            Datadog::Tracing::SpanOperation.new("root"),
            security_engine.new_runner,
          )
        end
        let(:security_engine) do
          Datadog::AppSec::SecurityEngine::Engine.new(appsec_settings: settings.appsec, telemetry: telemetry)
        end
        let(:settings) do
          Datadog::Core::Configuration::Settings.new.tap do |settings|
            settings.appsec.ruleset = {
              version: "2.2",
              rules: [
                {
                  id: "shallow-response-field",
                  name: "Shallow response field",
                  tags: {type: "test", category: "attack_attempt"},
                  conditions: [
                    {
                      operator: "match_regex",
                      parameters: {
                        inputs: [{address: "server.response.body", key_path: ["shallow"]}],
                        regex: "^keep$",
                      },
                    },
                  ],
                },
              ],
            }
          end
        end
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, inc: nil) }

        it "inspects shallow fields alongside deeply nested JSON" do
          expect { render_to_body }.to change { context.events.size }.from(0).to(1)
          expect(context.events.first.waf_result.events).to include(
            include("rule" => include("id" => "shallow-response-field")),
          )
        end
      end
    end

    context "when rendering JSONP" do
      subject(:render_to_body) { controller.render_to_body(json: serializer, callback: "app.callback") }

      before do
        unpatched_controller.request = ActionDispatch::Request.new({})
        unpatched_controller.response = ActionDispatch::Response.new
      end

      let(:unpatched_controller) { ActionController::Base.new }

      it "preserves Rails' response for the native decoder" do
        expect(render_to_body).to eq(
          unpatched_controller.render_to_body(json: {x: 1}, callback: "app.callback"),
        )
        expect(serializer.calls).to eq(1)
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: a_string_including("app.callback")),
        )
      end
    end

    context "when the callback is blank" do
      subject(:render_to_body) { controller.render_to_body(json: serializer, callback: " ") }

      it "inspects the JSON response without a callback wrapper" do
        expect(render_to_body).to eq('{"x":1}')
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: '{"x":1}'),
        )
      end
    end

    context "when the rendered response is invalid JSON" do
      subject(:render_to_body) { controller.render_to_body(json: "invalid JSON") }

      it "passes invalid JSON unchanged to the native decoder" do
        expect(render_to_body).to eq("invalid JSON")
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: "invalid JSON"),
        )
      end
    end

    context "when serialization fails" do
      before { allow(serializer).to receive(:as_json).and_raise(ArgumentError, "serialization failed") }

      it "propagates the application error" do
        expect { render_to_body }.to raise_error(ArgumentError, "serialization failed")
        expect(gateway).not_to have_received(:push)
      end
    end

    context "when a custom renderer returns a non-string body" do
      before { allow(controller).to receive(:_render_with_renderer_json).and_return(response_body) }

      let(:response_body) { ["streamed JSON"].each }

      it "preserves the body without consuming it" do
        expect(render_to_body).to equal(response_body)
        expect(response_body.next).to eq("streamed JSON")
        expect(gateway).not_to have_received(:push)
      end
    end

    context "when rendering a large JSON response" do
      subject(:render_to_body) { controller.render_to_body(json: response_body) }

      let(:response_body) { JSON.generate("value" => "x" * (4 * 1024 * 1024)) }

      it "passes the same string without copying the response" do
        expect(render_to_body).to equal(response_body)
        expect(gateway).to have_received(:push).with(
          "rails.response.body.json",
          have_attributes(data: equal(response_body)),
        )
      end
    end

    context "when AppSec blocks the response" do
      before do
        gateway.watch("rails.response.body.json") do |_stack, _container|
          throw Datadog::AppSec::Ext::INTERRUPT, :blocked
        end
      end

      it "propagates the interruption after a single serialization" do
        expect(catch(Datadog::AppSec::Ext::INTERRUPT) { render_to_body }).to eq(:blocked)
        expect(serializer.calls).to eq(1)
      end

      context "when Rails assigns the rendered response" do
        subject(:render_to_body) { controller.render(json: serializer) }

        it "interrupts before Rails assigns the response body" do
          expect(catch(Datadog::AppSec::Ext::INTERRUPT) { render_to_body }).to eq(:blocked)
          expect(controller.response_body).to be_nil
          expect(serializer.calls).to eq(1)
        end
      end
    end
  end
end
