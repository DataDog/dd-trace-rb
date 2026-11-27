require "spec_helper"

require "json"
require "msgpack"
require "securerandom"
require "stringio"
require "zlib"
require "datadog/core/utils/base64_codec"
require "datadog/core/remote/transport/http"
require "datadog/core/environment/agent_info"
require "datadog/core/telemetry/transport/http"
require "datadog/core/transport/http/adapters/native"
require "datadog/data_streams/transport/http"
require "datadog/di/guardrails_telemetry"
require "datadog/di/snapshot_event"
require "datadog/di/transport/http"
require "datadog/open_feature/transport"
require "datadog/symbol_database/transport/http"

# The agent consumers (remote configuration, telemetry, DI, ...) over the Net adapter and over the native one, against
# a real HTTP server.
#
# The specs of the consumers stub `Net::HTTP` or use WebMock, so they say nothing about what goes over the wire, and
# they cannot see the native client at all. Here the server is a real WEBrick one (see `HttpServerHelpers`): every
# example runs once per adapter, with the same expectations, so a difference between the two shows up as a failure of
# one of them.
#
# The native half needs the `libdatadog_api` extension built with a libdatadog that includes the HTTP client (see
# NATIVE_HTTP_SPECS in the Rakefile); without it, it is skipped.
RSpec.describe "Agent consumers over each HTTP adapter", :native_http do
  let(:logger) { logger_allowing_debug }

  # What the server received, in order: the verb, path, headers (lowercase names) and body of each request.
  let!(:requests) { [] }

  # path => [status, headers, body] or a proc that receives the WEBrick request and response. Anything else: 404.
  let(:routes) { {} }

  let(:timeout_seconds) { 5 }

  # `routes` and `requests` are read here, when the server is built, and not by the server thread: a `let` is not
  # available to another thread while the example thread is evaluating one (`subject(:response)`, for example), so the
  # request would wait for the client to give up.
  let(:server_proc) do
    requests = self.requests
    routes = self.routes

    proc do |req, res|
      requests << {
        verb: req.request_method,
        path: req.path,
        headers: req.header.transform_values(&:first),
        body: req.body,
      }

      route = routes.fetch(req.path) { [404, {}, "not found"] }
      if route.respond_to?(:call)
        route.call(req, res)
      else
        status, headers, body = route
        res.status = status
        headers.each { |name, value| res[name] = value }
        res.body = body
      end
    end
  end

  http_server do |http_server|
    http_server.mount_proc("/", &server_proc)
  end

  let(:agent_settings) do
    settings = Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.agent.host = "127.0.0.1"
      settings.agent.port = http_server_port
      settings.agent.timeout_seconds = timeout_seconds
    end

    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end

  shared_examples "remote configuration over the agent connection" do
    let(:info_body) do
      JSON.dump(
        {
          version: "42",
          endpoints: ["/info", "/v0/path"],
          config: {max_request_bytes: "1234"},
        },
      )
    end

    describe ".root" do
      subject(:transport) do
        Datadog::Core::Remote::Transport::HTTP.root(agent_settings: agent_settings, logger: logger)
      end

      describe "#send_info" do
        subject(:response) { transport.send_info }

        let(:routes) { {"/info" => [200, {"Content-Type" => "application/json"}, info_body]} }

        it "uses the expected adapter" do
          expect(transport.client.instance.adapter).to be_a(adapter_class)
        end

        it "returns the parsed response" do
          expect(response).to be_a(Datadog::Core::Remote::Transport::HTTP::Negotiation::Response)
          expect(response).to be_ok
          expect(response).to have_attributes(
            version: "42",
            endpoints: ["/info", "/v0/path"],
            config: {max_request_bytes: "1234"},
          )
        end

        it "sends a GET to /info with the default headers" do
          response

          expect(requests.size).to eq(1)
          expect(requests.first).to include(verb: "GET", path: "/info")
          expect(requests.first[:headers]).to include(
            "datadog-meta-lang" => Datadog::Core::Environment::Ext::LANG,
            "datadog-meta-lang-version" => Datadog::Core::Environment::Ext::LANG_VERSION,
          )
          expect(requests.first[:headers]).not_to include("datadog-client-computed-stats")
        end

        context "with APM tracing disabled" do
          before { allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false) }

          it "sends the computed stats header" do
            response

            expect(requests.first[:headers]).to include("datadog-client-computed-stats" => "yes")
          end
        end

        {
          404 => :not_found?,
          503 => :server_error?,
        }.each do |status, predicate|
          context "when the agent answers with #{status}" do
            let(:routes) { {"/info" => [status, {}, "not what you expected"]} }

            it "returns it as a response, not as an error" do
              expect(response.public_send(predicate)).to be(true)
              expect(response).not_to be_ok
              expect(response.internal_error?).to be_falsey
            end
          end
        end

        context "when the agent is down" do
          before do
            http_server.shutdown
            @server_thread.join
          end

          it "returns an internal error response, without raising" do
            expect(response.internal_error?).to be(true)
            expect(response.error).to be_a(StandardError)
          end
        end

        context "when the agent does not answer in time" do
          let(:timeout_seconds) { 1 }
          let(:routes) { {"/info" => proc { |_req, res| sleep(3) && res.status = 200 }} }

          # `Net::HTTP` retries an idempotent request once after a read timeout, so it takes about twice the timeout.
          it "returns an internal error response, once the timeout is over" do
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            expect(response.internal_error?).to be(true)
            expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
          end
        end
      end
    end

    describe ".v7" do
      subject(:transport) do
        Datadog::Core::Remote::Transport::HTTP.v7(agent_settings: agent_settings, logger: logger)
      end

      describe "#send_config" do
        subject(:response) { transport.send_config(payload) }

        let(:id) { SecureRandom.uuid }

        let(:payload) do
          {
            client: {
              state: {
                root_version: 1,
                targets_version: 0,
                config_states: [],
                has_error: false,
                error: "",
                backend_client_state: "",
              },
              id: id,
              products: [],
              is_tracer: true,
              is_agent: false,
              client_tracer: {
                runtime_id: Datadog::Core::Environment::Identity.id,
                language: Datadog::Core::Environment::Identity.lang,
                tracer_version: Datadog::Core::Environment::Identity.gem_datadog_version,
                service: "smoke",
                env: "test",
                tags: [],
              },
              capabilities: "",
            },
            cached_target_files: [],
          }
        end

        let(:config_body) do
          encode = proc { |value| Datadog::Core::Utils::Base64Codec.strict_encode64(value).chomp }
          json_encode = proc { |value| encode.call(JSON.dump(value)) }

          JSON.dump(
            {
              roots: [json_encode.call({}), json_encode.call({})],
              targets: json_encode.call(
                {
                  signed: {
                    expires: "2022-09-22T09:01:04Z",
                    targets: {
                      "datadog/42/PRODUCT/foo/config" => {
                        hashes: {sha256: "d0b425e00e15a0d36b9b361f02bab63563aed6cb4665083905386c55d5b679fa"},
                        length: 8,
                      },
                    },
                  },
                },
              ),
              target_files: [{path: "datadog/42/PRODUCT/foo/config", raw: encode.call("content1")}],
              client_configs: ["datadog/42/PRODUCT/foo/config"],
            },
          )
        end

        let(:routes) { {"/v0.7/config" => [200, {"Content-Type" => "application/json"}, config_body]} }

        it "uses the expected adapter" do
          expect(transport.client.instance.adapter).to be_a(adapter_class)
        end

        it "returns the parsed response" do
          expect(response).to be_a(Datadog::Core::Remote::Transport::HTTP::Config::Response)
          expect(response).to be_ok
          expect(response).to have_attributes(roots: be_a(Array), targets: be_a(Hash), target_files: be_a(Array))
          expect(response.target_files).to eq([{path: "datadog/42/PRODUCT/foo/config", content: "content1"}])
        end

        it "sends the payload as JSON in a POST to /v0.7/config" do
          response

          expect(requests.size).to eq(1)
          expect(requests.first).to include(verb: "POST", path: "/v0.7/config")
          expect(requests.first[:headers]["content-type"]).to include("application/json")

          sent = JSON.parse(requests.first[:body])
          expect(sent.dig("client", "id")).to eq(id)
          expect(sent.dig("client", "is_tracer")).to be(true)
          expect(sent.dig("client", "client_tracer", "service")).to eq("smoke")
        end
      end
    end

    context "when the agent is listening on a Unix socket" do
      define_http_server_uds do |http_server|
        http_server.mount_proc("/", &server_proc)
      end

      let(:agent_settings) do
        settings = Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.agent.uds_path = uds_socket_path
          settings.agent.timeout_seconds = timeout_seconds
        end

        Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
      end

      let(:routes) { {"/info" => [200, {"Content-Type" => "application/json"}, info_body]} }

      subject(:transport) do
        Datadog::Core::Remote::Transport::HTTP.root(agent_settings: agent_settings, logger: logger)
      end

      it "uses the expected adapter" do
        expect(transport.client.instance.adapter).to be_a(unix_socket_adapter_class)
      end

      it "gets the response through the socket" do
        response = transport.send_info

        expect(response).to be_ok
        expect(response).to have_attributes(version: "42")
        expect(requests.first).to include(verb: "GET", path: "/info")
      end
    end
  end

  shared_examples "agent information over the agent connection" do
    subject(:agent_info) { Datadog::Core::Environment::AgentInfo.new(agent_settings, logger: logger) }

    let(:container_tags_hash) { "abc123" }
    let(:routes) do
      {
        "/info" => [
          200,
          {"Content-Type" => "application/json", "Datadog-Container-Tags-Hash" => container_tags_hash},
          JSON.dump({version: "42", endpoints: ["/info"], config: {}}),
        ],
      }
    end

    before { allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true) }

    # The propagation checksum is computed from the process tags and the container tags hash, which the agent sends in a
    # response header.
    def checksum(container_tags_hash)
      Datadog::Core::Utils::FNV.fnv1_64(Datadog::Core::Environment::Process.serialized + container_tags_hash.to_s)
    end

    it "fetches the information from the agent" do
      expect(agent_info.fetch).to be_ok
      expect(requests.map { |request| request[:path] }).to eq(["/info"])
    end

    it "uses the container tags hash of the response headers, if the adapter exposes them" do
      agent_info.fetch

      expect(agent_info.propagation_checksum).to eq(checksum(reads_response_headers ? container_tags_hash : nil))
    end
  end

  shared_examples "telemetry over the agent connection" do
    subject(:transport) do
      Datadog::Core::Telemetry::Transport::HTTP.agent_telemetry(agent_settings: agent_settings, logger: logger)
    end

    let(:routes) { {"/telemetry/proxy/api/v2/apmtelemetry" => [202, {}, ""]} }

    it "uses the expected adapter" do
      expect(transport.client.instance.adapter).to be_a(adapter_class)
    end

    it "sends the payload as JSON, with the telemetry headers" do
      response = transport.send_telemetry(request_type: "app-started", payload: {"hello" => "world"})

      expect(response).to be_ok
      expect(requests.size).to eq(1)
      expect(requests.first).to include(verb: "POST", path: "/telemetry/proxy/api/v2/apmtelemetry")
      expect(requests.first[:headers]).to include(
        "dd-telemetry-request-type" => "app-started",
        "dd-telemetry-api-version" => "v2",
        "dd-client-library-language" => Datadog::Core::Environment::Ext::LANG,
        "dd-internal-untraced-request" => "1",
      )
      expect(requests.first[:headers]["content-type"]).to include("application/json")
      expect(JSON.parse(requests.first[:body])).to eq("hello" => "world")
    end
  end

  shared_examples "dynamic instrumentation over the agent connection" do
    let(:diagnostics_path) { "/debugger/v1/diagnostics" }
    let(:input_path) { "/debugger/v2/input" }

    describe "diagnostics" do
      subject(:transport) do
        Datadog::DI::Transport::HTTP.diagnostics(agent_settings: agent_settings, logger: logger)
      end

      let(:routes) { {diagnostics_path => [200, {}, ""]} }

      it "uses the expected adapter" do
        expect(transport.client.instance.adapter).to be_a(adapter_class)
      end

      it "sends the payload as the multipart event.json part" do
        response = transport.send_diagnostics({"probe" => "status"})

        expect(response).to be_ok
        expect(requests.size).to eq(1)
        expect(requests.first).to include(verb: "POST", path: diagnostics_path)
        expect(requests.first[:headers]["content-type"]).to start_with("multipart/form-data; boundary=")
        expect(requests.first[:body]).to include('name="event"', 'filename="event.json"', "application/json", '{"probe":"status"}')
      end
    end

    describe "input" do
      subject(:transport) do
        Datadog::DI::Transport::HTTP.input(
          agent_settings: agent_settings, logger: logger, guardrails_telemetry: guardrails_telemetry,
        )
      end

      let(:guardrails_telemetry) do
        Datadog::DI::GuardrailsTelemetry.new(
          settings: Datadog::Core::Configuration::Settings.new, logger: logger, telemetry: nil,
        )
      end
      let(:events) do
        [Datadog::DI::SnapshotEvent.new(
          payload: {debugger: {snapshot: {probe: {id: "probe-1"}}}},
          event_type: Datadog::DI::GuardrailsTelemetry::EVENT_TYPE_SNAPSHOT,
        )]
      end
      let(:send_input) { transport.send_input(events, {env: "test"}, on_serialization_error: proc {}) }

      context "when the agent has the v2 endpoint" do
        let(:routes) { {input_path => [200, {}, ""]} }

        it "uses the expected adapter" do
          expect(transport.client.instance.adapter).to be_a(adapter_class)
        end

        it "sends the snapshots as JSON, with the tags in the query" do
          send_input

          expect(requests.size).to eq(1)
          expect(requests.first).to include(verb: "POST", path: input_path)
          expect(requests.first[:headers]["content-type"]).to include("application/json")
          expect(JSON.parse(requests.first[:body])).to eq(
            [{"debugger" => {"snapshot" => {"probe" => {"id" => "probe-1"}}}}],
          )
        end
      end

      context "when the agent does not have the v2 endpoint" do
        let(:routes) { {input_path => [404, {}, "not found"], diagnostics_path => [200, {}, ""]} }

        it "falls back to the legacy endpoint" do
          send_input

          expect(requests.map { |request| request[:path] }).to eq([input_path, diagnostics_path])
          expect(JSON.parse(requests.last[:body]))
            .to eq([{"debugger" => {"snapshot" => {"probe" => {"id" => "probe-1"}}}}])
        end
      end
    end
  end

  shared_examples "symbol database over the agent connection" do
    subject(:transport) do
      Datadog::SymbolDatabase::Transport::HTTP.symbols(agent_settings: agent_settings, logger: logger)
    end

    let(:compressed_symbols) { Zlib.gzip('{"scopes":[]}') }
    let(:form) do
      upload = Datadog::Core::Vendor::Multipart::Post::UploadIO
      {
        "event" => upload.new(StringIO.new('{"ddsource":"ruby","type":"symdb"}'), "application/json", "event.json"),
        "file" => upload.new(StringIO.new(compressed_symbols), "application/gzip", "symbols.json.gz"),
      }
    end
    let(:routes) { {"/symdb/v1/input" => [200, {}, ""]} }

    it "uses the expected adapter" do
      expect(transport.client.instance.adapter).to be_a(adapter_class)
    end

    it "uploads the parts as multipart/form-data" do
      response = transport.send_symbols(form)

      expect(response.code).to eq(200)
      expect(requests.size).to eq(1)
      expect(requests.first).to include(verb: "POST", path: "/symdb/v1/input")
      expect(requests.first[:headers]["content-type"]).to start_with("multipart/form-data; boundary=")

      body = requests.first[:body].b
      expect(body).to include('name="event"', 'filename="event.json"', "application/json", '"ddsource":"ruby"')
      expect(body).to include('name="file"', 'filename="symbols.json.gz"', "application/gzip")
      expect(body).to include(compressed_symbols.b)
    end

    context "when the agent answers with a 4xx" do
      let(:routes) { {"/symdb/v1/input" => [400, {}, "bad request"]} }

      it "returns it as a response, not as an error" do
        response = transport.send_symbols(form)

        expect(response.code).to eq(400)
        expect(response.internal_error?).to be_falsey
      end
    end
  end

  shared_examples "feature flags over the agent connection" do
    let(:routes) do
      {
        "/evp_proxy/v2/api/v2/exposures" => [201, {}, ""],
        "/evp_proxy/v2/api/v2/flagevaluation" => [201, {}, ""],
      }
    end

    {
      send_exposures: [:build, "/evp_proxy/v2/api/v2/exposures"],
      send_flag_evaluations: [:build_flagevaluations, "/evp_proxy/v2/api/v2/flagevaluation"],
    }.each do |method, (builder, path)|
      describe "##{method}" do
        subject(:transport) do
          Datadog::OpenFeature::Transport::HTTP.public_send(builder, agent_settings: agent_settings, logger: logger)
        end

        it "uses the expected adapter" do
          # The transport does not expose its API instance.
          expect(transport.instance_variable_get(:@api).adapter).to be_a(adapter_class)
        end

        it "sends the JSON payload and the SDK identity" do
          response = transport.public_send(method, "event" => "value")

          expect(response.code).to eq(201)
          expect(requests.size).to eq(1)
          expect(requests.first).to include(verb: "POST", path: path, body: '{"event":"value"}')
          expect(requests.first[:headers]).to include(
            "dd-evp-origin" => "dd-trace-rb",
            "dd-evp-origin-version" => Datadog::VERSION::STRING,
            "x-datadog-evp-subdomain" => "event-platform-intake",
          )
          expect(requests.first[:headers]["content-type"]).to include("application/json")
        end
      end
    end
  end

  shared_examples "data streams over the agent connection" do
    subject(:transport) { Datadog::DataStreams::Transport::HTTP.default(agent_settings: agent_settings, logger: logger) }

    let(:routes) { {"/v0.1/pipeline_stats" => [200, {}, ""]} }

    it "uses the expected adapter" do
      expect(transport.client.instance.adapter).to be_a(adapter_class)
    end

    it "sends the stats as gzipped msgpack" do
      response = transport.send_stats("key" => "value")

      expect(response).to be_ok
      expect(requests.size).to eq(1)
      expect(requests.first).to include(verb: "POST", path: "/v0.1/pipeline_stats")
      expect(requests.first[:headers]).to include(
        "content-type" => "application/msgpack",
        "content-encoding" => "gzip",
      )
      expect(MessagePack.unpack(Zlib.gunzip(requests.first[:body]))).to eq("key" => "value")
    end
  end

  context "with the Net adapter" do
    before { allow(Datadog.configuration.agent).to receive(:native_http).and_return(false) }

    let(:adapter_class) { Datadog::Core::Transport::HTTP::Adapters::Net }
    let(:unix_socket_adapter_class) { Datadog::Core::Transport::HTTP::Adapters::UnixSocket }
    # The response of the Net adapter does not have headers.
    let(:reads_response_headers) { false }

    it_behaves_like "remote configuration over the agent connection"
    it_behaves_like "agent information over the agent connection"
    it_behaves_like "telemetry over the agent connection"
    it_behaves_like "dynamic instrumentation over the agent connection"
    it_behaves_like "symbol database over the agent connection"
    it_behaves_like "feature flags over the agent connection"
    it_behaves_like "data streams over the agent connection"
  end

  context "with the native adapter" do
    before do
      if (reason = Datadog::Core::Transport::HTTP::Adapters::Native.unsupported_reason)
        skip "The native HTTP client is not available: #{reason}"
      end

      allow(Datadog.configuration.agent).to receive(:native_http).and_return(true)
    end

    let(:adapter_class) { Datadog::Core::Transport::HTTP::Adapters::Native }
    let(:unix_socket_adapter_class) { Datadog::Core::Transport::HTTP::Adapters::Native }
    let(:reads_response_headers) { true }

    it_behaves_like "remote configuration over the agent connection"
    it_behaves_like "agent information over the agent connection"
    it_behaves_like "telemetry over the agent connection"
    it_behaves_like "dynamic instrumentation over the agent connection"
    it_behaves_like "symbol database over the agent connection"
    it_behaves_like "feature flags over the agent connection"
    it_behaves_like "data streams over the agent connection"
  end
end
