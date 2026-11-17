# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/appsec/spec_helper"
require "rack/test"
require "rack"

RSpec.describe Datadog::AppSec::Contrib::Rack::RequestMiddleware do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack

      c.appsec.enabled = true
      c.appsec.instrument :rack
      c.appsec.waf_timeout = 10_000_000
      c.appsec.api_security.enabled = false

      c.remote.enabled = false
    end

    allow(Datadog.logger).to receive(:warn)
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport)
      .to receive(:native_events_supported?).and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:app) do
    rack_endpoint = endpoint
    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      run(rack_endpoint)
    end.to_app
  end

  describe "#call" do
    context "when the app is interrupted" do
      before { get("/") }

      let(:endpoint) do
        proc do
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401", "type" => "json"})
          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(401) }
      it { expect(last_response.headers["Content-Type"]).to eq("application/json") }
    end

    context "when another thread interrupts the request and the app completes" do
      before { get("/") }

      let(:endpoint) do
        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]

          Thread.new { context.catch_interrupt { context.interrupt!({"status_code" => "401"}) } }.join

          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(200) }
    end

    context "when the app is interrupted while another thread is attached" do
      before { get("/") }
      after { contexts.each(&:detach) }

      let(:contexts) { [] }
      let(:endpoint) do
        attached_contexts = contexts

        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]
          context.attach
          attached_contexts << context

          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401"})
          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(401) }
    end

    context "when the response check is interrupted" do
      before do
        allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401"}) if name == "rack.response"

          method.call(name, *args, &block)
        end

        get("/")
      end

      let(:endpoint) { proc { [200, {"content-type" => "text/plain"}, ["OK"]] } }

      it { expect(last_response.status).to eq(401) }
    end

    context "when the response check is interrupted while another thread is attached" do
      before do
        allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401"}) if name == "rack.response"

          method.call(name, *args, &block)
        end

        get("/")
      end

      after { contexts.each(&:detach) }

      let(:contexts) { [] }
      let(:endpoint) do
        attached_contexts = contexts

        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]
          context.attach
          attached_contexts << context

          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it "returns the app response" do
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("OK")
      end
    end

    context "when another thread made the first decision and the app is interrupted" do
      before { get("/") }

      let(:endpoint) do
        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]

          Thread.new do
            context.catch_interrupt { context.interrupt!({"status_code" => "303", "location" => +"/blocked", "security_response_id" => "id"}) }
          end.join

          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401"})
          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it "renders the first decision" do
        expect(last_response.status).to eq(303)
        expect(last_response.headers["Location"]).to eq("/blocked")
      end
    end
  end
end
