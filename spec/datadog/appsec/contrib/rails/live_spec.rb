# frozen_string_literal: true

require "datadog/tracing/contrib/rails/rails_helper"
require "rack/test"
require "timeout"

require "datadog/tracing"
require "datadog/appsec"

RSpec.describe "AppSec Rails integration with ActionController::Live", execute_in_fork: Rails.version.to_i >= 8 do
  include Rack::Test::Methods
  include_context "Rails test application"

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails

      c.appsec.enabled = true
      c.appsec.rasp_enabled = true
      c.appsec.instrument :rails
      c.appsec.instrument :active_record
      c.appsec.ruleset = {
        rules: [
          {
            id: "rasp-003-001",
            name: "SQL Injection",
            tags: {type: "sql_injection", category: "exploit", module: "rasp"},
            conditions: [
              {
                operator: "sqli_detector",
                parameters: {
                  resource: [{address: "server.db.statement"}],
                  params: [{address: "server.request.query"}],
                  db_type: [{address: "server.db.system"}],
                },
              },
            ],
            on_match: ["block"],
          },
        ],
      }
    end

    allow(Datadog.logger).to receive(:warn)
    allow(ActionController::Base).to receive(:logger).and_return(Logger.new(rails_log))
    allow_any_instance_of(Datadog::AppSec::Context).to receive(:detach).and_wrap_original do |method|
      method.call
      live_signals[:detached].push(Thread.current)
    end
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rails].reset_configuration!
  end

  let(:rails_log) { StringIO.new }
  let(:routes) do
    {
      "/live" => "live#stream",
      "/live/current_context" => "live#current_context",
      "/live/query_before_commit" => "live#query_before_commit",
      "/live/query_after_write" => "live#query_after_write",
      "/live/query_after_close" => "live#query_after_close",
      "/live/query_after_response_body" => "live#query_after_response_body",
      "/live/safe_query_after_write" => "live#safe_query_after_write",
    }
  end
  let(:controllers) { [controller] }
  let(:controller) do
    signals = live_signals

    stub_const(
      "LiveController",
      Class.new(ActionController::Base) do
        include ActionController::Live

        after_action only: :stream do
          signals[:resumed].pop

          signals[:result].push(
            begin
              [Datadog::AppSec.active_context, ActiveRecord::Base.connection.select_value("SELECT 1")]
            rescue => e
              e
            end,
          )
        end

        def stream
          response.stream.write("ok")
        ensure
          response.stream.close
        end

        define_method(:current_context) do
          signals[:result].push([Datadog::AppSec.active_context, request.env[Datadog::AppSec::Ext::CONTEXT_KEY]])

          response.stream.write("ok")
          response.stream.close
        end

        define_method(:query_before_commit) do
          signals[:steps] << :before_query
          ActiveRecord::Base.connection.select_value("SELECT '#{params[:name]}'")
          signals[:steps] << :after_query

          response.stream.write("ok")
          response.stream.close
        end

        define_method(:query_after_write) do
          response.headers["Last-Modified"] = "Wed, 21 Oct 2015 07:28:00 GMT"
          signals[:streams] << response.stream
          response.stream.write("ok")

          signals[:resumed].pop
          signals[:steps] << :before_query
          ActiveRecord::Base.connection.select_value("SELECT '#{params[:name]}'")
          signals[:steps] << :after_query

          response.stream.close
        end

        define_method(:query_after_close) do
          response.stream.close

          signals[:resumed].pop
          signals[:steps] << :before_query
          ActiveRecord::Base.connection.select_value("SELECT '#{params[:name]}'")
          signals[:steps] << :after_query
        end

        define_method(:query_after_response_body) do
          self.response_body = "ok"

          signals[:resumed].pop
          signals[:steps] << :before_query
          ActiveRecord::Base.connection.select_value("SELECT '#{params[:name]}'")
          signals[:steps] << :after_query
        end

        define_method(:safe_query_after_write) do
          response.headers["Last-Modified"] = "Wed, 21 Oct 2015 07:28:00 GMT"
          response.stream.write("ok")

          signals[:resumed].pop
          signals[:result].push(ActiveRecord::Base.connection.select_value("SELECT 1"))
          signals[:decided].pop

          response.stream.close
        end
      end,
    )
  end
  let(:live_signals) do
    {resumed: Queue.new, result: Queue.new, detached: Queue.new, decided: Queue.new, steps: [], streams: []}
  end
  let(:after_action_result) do
    Timeout.timeout(5) do
      get_live("/live")
      live_signals[:resumed].push(true)
      live_signals[:result].pop
    end
  end

  def get_live(path, params = {})
    get(path, params, {"SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/1.1"})
  end

  def wait_for_controller_thread
    Timeout.timeout(5) do
      loop { break unless live_signals[:detached].pop == Thread.current }
    end
  end

  def stream_after_request_thread_returned(path)
    Timeout.timeout(5) do
      status, _headers, body = app.call(Rack::MockRequest.env_for(path, params: {"name" => "1' OR '1'='1"}))
      live_signals[:resumed].push(true)

      chunks = []
      body.each { |chunk| chunks << chunk }
      body.close
      wait_for_controller_thread

      [status, chunks.join]
    end
  end

  context "when after_action runs a query after the request ended in the request thread" do
    it "runs the query without error" do
      expect(after_action_result).not_to be_a(Exception)
      expect(after_action_result.last).to eq(1)
    end

    it "keeps AppSec context in the live thread" do
      skip "Live thread hand-off hook exists only since Rails 5" if Rails::VERSION::MAJOR < 5

      expect(after_action_result).not_to be_a(Exception)
      expect(after_action_result.first).to be_a(Datadog::AppSec::Context)
    end
  end

  context "when live thread is blocked while request thread waits for commit" do
    before do
      Timeout.timeout(5) { get_live("/live/query_before_commit", {"name" => "1' OR '1'='1"}) }
      wait_for_controller_thread
    end

    it { expect(last_response.status).to eq(200) }
    it { expect(live_signals[:steps]).to eq([:before_query]) }
  end

  context "when live thread is blocked after request thread returned" do
    it "ends the stream without running the query" do
      expect(stream_after_request_thread_returned("/live/query_after_write")).to eq([200, "ok"])
      expect(live_signals[:steps]).to eq([:before_query])
    end

    it "does not log live thread errors" do
      stream_after_request_thread_returned("/live/query_after_write")

      expect(rails_log.string).not_to include("FATAL")
      expect(rails_log.string).not_to include("UncaughtThrowError")
    end
  end

  context "when live thread is blocked after stream was closed and request thread returned" do
    it "does not run the query" do
      expect(stream_after_request_thread_returned("/live/query_after_close").first).to eq(200)
      expect(live_signals[:steps]).to eq([:before_query])
      expect(rails_log.string).not_to include("FATAL")
    end
  end

  context "when live thread is blocked after response body was set and request thread returned" do
    it "does not run the query" do
      expect(stream_after_request_thread_returned("/live/query_after_response_body").first).to eq(200)
      expect(live_signals[:steps]).to eq([:before_query])
      expect(rails_log.string).not_to include("FATAL")
    end
  end

  context "when live thread is blocked while request thread runs response checks" do
    before do
      allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
        if name == "rack.response"
          live_signals[:resumed].push(true)
          wait_for_controller_thread
        end

        method.call(name, *args, &block)
      end

      Timeout.timeout(5) { get_live("/live/query_after_write", {"name" => "1' OR '1'='1"}) }
    end

    it { expect(last_response.status).to eq(200) }
    it { expect(last_response.body).to eq("ok") }
    it { expect(live_signals[:steps]).to eq([:before_query]) }
    it { expect(live_signals[:streams].first).to be_closed }
  end

  context "when request thread is blocked in response checks while live thread works" do
    before do
      allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
        if name == "rack.response"
          live_signals[:resumed].push(true)
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "403"})
        end

        method.call(name, *args, &block)
      end
      allow_any_instance_of(Datadog::AppSec::Context).to receive(:run_rasp).and_wrap_original do |method, *args, **kwargs|
        rasp_threads << Thread.current
        method.call(*args, **kwargs)
      end
      allow_any_instance_of(Datadog::AppSec::Context).to receive(:shared?).and_wrap_original do |method|
        method.call.tap { live_signals[:decided].push(true) }
      end

      Timeout.timeout(5) do
        get_live("/live/safe_query_after_write")
        wait_for_controller_thread
      end
    end

    let(:rasp_threads) { [] }

    it { expect(last_response.status).to eq(200) }
    it { expect(last_response.body).to eq("ok") }
    it { expect(live_signals[:result].pop).to eq(1) }
    it { expect(rasp_threads).to include(satisfy { |thread| thread != Thread.current }) }
  end

  context "when request thread is blocked in response checks after live thread ended" do
    before do
      allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
        if name == "rack.response"
          wait_for_controller_thread
          Datadog::AppSec::ActionsHandler.interrupt_execution({"status_code" => "403"})
        end

        method.call(name, *args, &block)
      end

      Timeout.timeout(5) { get_live("/live/current_context") }
    end

    it { expect(last_response.status).to eq(403) }
  end

  context "when live thread ends before request thread returns" do
    before do
      allow(Datadog::AppSec::Instrumentation.gateway).to receive(:push).and_wrap_original do |method, name, *args, &block|
        wait_for_controller_thread if name == "rack.response"

        method.call(name, *args, &block)
      end
      allow_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:finalize!).and_wrap_original do |method|
        finalized_threads << Thread.current
        method.call
      end

      Timeout.timeout(5) { get_live("/live/current_context") }
    end

    let(:finalized_threads) { [] }

    it { expect(finalized_threads).to eq([Thread.current]) }
  end

  context "when request thread returns before live thread ends" do
    before do
      allow_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:finalize!).and_wrap_original do |method|
        finalized_threads << Thread.current
        method.call
      end

      after_action_result
      wait_for_controller_thread
    end

    let(:finalized_threads) { [] }

    it "frees the WAF once in the live thread" do
      expect(finalized_threads.size).to eq(1)
      expect(finalized_threads.first).not_to eq(Thread.current)
    end
  end

  context "when two live requests run one after the other" do
    before do
      Timeout.timeout(5) do
        get_live("/live/current_context")
        get_live("/live/current_context")
      end
    end

    it "sees the context of the current request" do
      first_request_contexts = live_signals[:result].pop
      second_request_contexts = live_signals[:result].pop

      expect(second_request_contexts.first).to eq(second_request_contexts.last)
      expect(second_request_contexts.first).not_to eq(first_request_contexts.first)
    end
  end
end
