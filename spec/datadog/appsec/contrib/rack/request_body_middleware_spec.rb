# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/appsec/spec_helper"
require "rack/test"
require "rack"

RSpec.describe Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware do
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
    endpoint = rack_endpoint
    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware

      run(endpoint)
    end.to_app
  end

  describe "#call" do
    context "when the app is interrupted" do
      before { post("/", "name=value") }

      let(:rack_endpoint) do
        proc do
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401", "type" => "json"})
          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(401) }
      it { expect(last_response.headers["Content-Type"]).to eq("application/json") }
    end

    context "when another thread interrupts the request and the app completes" do
      before { post("/", "name=value") }

      let(:rack_endpoint) do
        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]

          Thread.new { context.catch { context.interrupt!({"status_code" => "401"}) } }.join

          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(200) }
    end

    context "when the app is interrupted while another thread is attached" do
      before { post("/", "name=value") }

      after { attached_contexts.each(&:detach) }

      let(:attached_contexts) { [] }
      let(:rack_endpoint) do
        contexts = attached_contexts

        proc do |env|
          context = env[Datadog::AppSec::Ext::CONTEXT_KEY]
          context.attach
          contexts << context

          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "401"})
          [200, {"content-type" => "text/plain"}, ["OK"]]
        end
      end

      it { expect(last_response.status).to eq(401) }
    end
  end
end
