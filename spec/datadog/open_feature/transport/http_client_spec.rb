# frozen_string_literal: true

require "spec_helper"
require "socket"
require "datadog/open_feature/transport/http_client"

RSpec.describe Datadog::OpenFeature::Transport::HTTPClient, webmock: true do
  subject(:client) { described_class.new(agent_settings: agent_settings, site: site, api_key: "secret-test-key") }

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettings.new(adapter: :net_http, hostname: "localhost", port: 8126, ssl: false)
  end
  let(:site) { "datadoghq.com" }
  let(:direct_url) { "https://event-platform-intake.datadoghq.com/api/v2/exposures" }
  let(:identity) { {"DD-EVP-ORIGIN" => "dd-trace-rb", "DD-EVP-ORIGIN-VERSION" => Datadog::VERSION::STRING} }

  around do |example|
    ClimateControl.modify("http_proxy" => nil, "HTTP_PROXY" => nil, "https_proxy" => nil,
      "HTTPS_PROXY" => nil, "no_proxy" => nil, "NO_PROXY" => nil) { example.run }
  end

  %w[https_proxy HTTPS_PROXY].each do |name|
    it "treats empty #{name} as disabled proxying" do
      ClimateControl.modify(name => "") do
        expect(client.send(:connection, true).proxy?).to be(false)
      end
    end
  end

  it "normalizes API keys like agentless configuration delivery" do
    sender = described_class.new(agent_settings: agent_settings, site: site, api_key: " secret-test-key\n")
    direct = stub_request(:post, direct_url).with(headers: {"DD-API-KEY" => "secret-test-key"}).to_return(status: 202)
    expect(sender).to be_direct
    expect(sender.request("/api/v2/exposures", payload: "{}", direct: true, timeout: 1)).to be_ok
    expect(direct).to have_been_requested.once
  end

  [nil, "", " \n", "secret\nother", "secret\rother"].each do |invalid_key|
    it "rejects an empty or embedded-newline API key #{invalid_key.inspect}" do
      sender = described_class.new(agent_settings: agent_settings, site: site, api_key: invalid_key)
      expect(sender).not_to be_direct
    end
  end

  it "isolates credentials, preserves identity and sends identical bytes on both routes" do
    payload = '{"events":[{"flag":"a"}]}'
    local = stub_request(:post, "http://localhost:8126/evp_proxy/v4/api/v2/exposures")
      .with(body: payload, headers: identity.merge("X-Datadog-EVP-Subdomain" => "event-platform-intake"))
      .with { |request| !request.headers.key?("Dd-Api-Key") }.to_return(status: 202)
    direct = stub_request(:post, direct_url).with(body: payload, headers: identity.merge("DD-API-KEY" => "secret-test-key"))
      .with { |request| !request.headers.key?("X-Datadog-Evp-Subdomain") }.to_return(status: 202)
    expect(client.request("/evp_proxy/v4/api/v2/exposures", payload: payload, timeout: 1)).to be_ok
    expect(client.request("/api/v2/exposures", payload: payload, direct: true, timeout: 1)).to be_ok
    expect(local).to have_been_requested.once
    expect(direct).to have_been_requested.once
  end

  [301, 302, 307, 308].each do |status|
    it "refuses direct redirects (#{status})" do
      stub_request(:post, direct_url).to_return(status: status, headers: {"Location" => "https://other.invalid/steal"})
      result = client.request("/api/v2/exposures", payload: "{}", direct: true, timeout: 1)
      expect(result.code).to eq(status)
      expect(a_request(:any, "https://other.invalid/steal")).not_to have_been_made
    end
  end

  ["user@site.com", "site.com:443", "site.com/a", "site.com?x", "site.com#x", "site%2ecom",
    "site\\evil.com", "site\u3002com", "bad_site.com", ".site.com", "site..com", "site.com.",
    "-site.com", "site-.com", "s" * 64 + ".com", "site\n.com"].each do |invalid_site|
    context "with invalid site #{invalid_site.inspect}" do
      let(:site) { invalid_site }

      it "disables direct delivery before sending any credentials" do
        expect(client).not_to be_direct
        expect(client.request("/api/v2/exposures", payload: "{}", direct: true, timeout: 1)).not_to be_ok
      end
    end
  end

  context "with surrounding site whitespace and uppercase" do
    let(:site) { " DATADOGHQ.COM \n" }

    it "uses a canonical HTTPS host" do
      direct = stub_request(:post, direct_url).to_return(status: 202)
      expect(client.request("/api/v2/exposures", payload: "{}", direct: true, timeout: 1)).to be_ok
      expect(direct).to have_been_requested.once
    end
  end

  it "preserves a configured prefix for discovery and delivery" do
    ClimateControl.modify("DD_TRACE_AGENT_URL" => "http://localhost:8126/gateway/v0.4/traces") do
      info = stub_request(:get, "http://localhost:8126/gateway/info").to_return(body: '{"endpoints":[]}')
      local = stub_request(:post, "http://localhost:8126/gateway/evp_proxy/v4/api/v2/exposures").to_return(status: 202)
      expect(client.request("/info", timeout: 1).info).to eq("endpoints" => [])
      client.request("/evp_proxy/v4/api/v2/exposures", payload: "{}", timeout: 1)
      expect(info).to have_been_requested.once
      expect(local).to have_been_requested.once
    end
  end

  it "retains the prefix when the resolved DNS hostname differs only in case" do
    ClimateControl.modify("DD_TRACE_AGENT_URL" => "http://LOCALHOST:8126/gateway/v0.4/traces") do
      info = stub_request(:get, "http://localhost:8126/gateway/info").to_return(body: '{"endpoints":[]}')
      local = stub_request(:post, "http://localhost:8126/gateway/evp_proxy/v4/api/v2/exposures").to_return(status: 202)
      expect(client.request("/info", timeout: 1).info).to eq("endpoints" => [])
      client.request("/evp_proxy/v4/api/v2/exposures", payload: "{}", timeout: 1)
      expect(info).to have_been_requested.once
      expect(local).to have_been_requested.once
    end
  end

  it "does not attach a prefix from an overridden endpoint" do
    ClimateControl.modify("DD_TRACE_AGENT_URL" => "http://other:8126/gateway") do
      request = stub_request(:get, "http://localhost:8126/info").to_return(body: "{}")
      client.request("/info", timeout: 1)
      expect(request).to have_been_requested.once
    end
  end

  ["not json", "[]", "x" * 65_537].each do |body|
    it "rejects malformed or oversized discovery (#{body.length} bytes)" do
      stub_request(:get, "http://localhost:8126/info").to_return(body: body)
      expect(client.request("/info", timeout: 1).info).to be_nil
    end
  end

  it "honors Ruby proxy discovery for direct HTTPS while bypassing it locally" do
    ClimateControl.modify("http_proxy" => "http://user:pass@proxy.invalid:8080", "no_proxy" => nil) do
      direct = client.send(:connection, true)
      expect(direct.proxy_address).to eq("proxy.invalid")
      expect(direct.proxy_port).to eq(8080)
      expect(direct).to be_use_ssl
      expect(client.send(:connection, false).proxy?).to be(false)
    end
  end

  it "honors no_proxy for direct intake" do
    ClimateControl.modify("http_proxy" => "http://proxy.invalid:8080", "no_proxy" => "datadoghq.com") do
      expect(client.send(:connection, true).proxy?).to be(false)
    end
  end

  it "uses the HTTPS proxy and honors its no_proxy exclusion" do
    ClimateControl.modify("HTTPS_PROXY" => "http://user:pass@proxy.invalid:8080", "no_proxy" => nil) do
      connection = client.send(:connection, true)
      expect(connection.proxy_address).to eq("proxy.invalid")
      expect(connection.proxy_user).to eq("user")
      expect(connection.proxy_pass).to eq("pass")
      ClimateControl.modify("no_proxy" => "datadoghq.com") do
        expect(client.send(:connection, true).proxy?).to be(false)
      end
    end
  end

  it "supports discovery and delivery over Unix domain sockets" do
    WebMock.disable!
    Dir.mktmpdir do |directory|
      path = File.join(directory, "agent.sock")
      server = UNIXServer.new(path)
      settings = Datadog::Core::Configuration::AgentSettings.new(adapter: :unix, uds_path: path)
      sender = described_class.new(agent_settings: settings, site: nil, api_key: nil)
      requests = Queue.new
      receiver = Thread.new do
        2.times do
          socket = server.accept
          headers = +""
          headers << socket.readline until headers.end_with?("\r\n\r\n")
          requests << headers
          body = '{"endpoints":[]}'
          socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
          socket.close
        end
      end
      expect(sender.request("/info", timeout: 1).info).to eq("endpoints" => [])
      expect(sender.request("/evp_proxy/v2/api/v2/exposures", payload: "{}", timeout: 1)).to be_ok
      expect(receiver.join(2)).to eq(receiver)
      expect(requests.pop).to start_with("GET /info ")
      expect(requests.pop).to include("POST /evp_proxy/v2/api/v2/exposures ", "Dd-Evp-Origin: dd-trace-rb")
    ensure
      server&.close
      receiver&.kill
      receiver&.join(1)
    end
  end

  context "using real sockets" do
    before { WebMock.disable! }

    let(:server) { TCPServer.new("127.0.0.1", 0) }
    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(adapter: :net_http, hostname: "127.0.0.1", port: server.addr[1], ssl: false)
    end

    after { server.close }

    it "keeps intake credentials and payload out of the proxy CONNECT request" do
      captured = Queue.new
      receiver = Thread.new do
        socket = server.accept
        headers = +""
        headers << socket.readline until headers.end_with?("\r\n\r\n")
        captured << headers
        socket.write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
        socket.close
      end
      ClimateControl.modify("HTTPS_PROXY" => "http://proxy-user:proxy-pass@127.0.0.1:#{server.addr[1]}", "no_proxy" => nil, "NO_PROXY" => nil) do
        expect(client.request("/api/v2/exposures", payload: "private-event", direct: true, timeout: 1)).not_to be_ok
      end
      expect(receiver.join(2)).to eq(receiver)
      headers = captured.pop
      expect(headers).to start_with("CONNECT event-platform-intake.datadoghq.com:443 ")
      expect(headers).to include("Proxy-Authorization: Basic ")
      expect(headers.downcase).not_to include("dd-api-key", "secret-test-key", "private-event", "dd-evp-origin")
    ensure
      receiver&.kill
      receiver&.join(1)
    end

    it "closes a connection that times out during TLS negotiation without waiting for GC" do
      settings = Datadog::Core::Configuration::AgentSettings.new(adapter: :net_http,
        hostname: "127.0.0.1", port: server.addr[1], ssl: true)
      sender = described_class.new(agent_settings: settings, site: nil, api_key: nil)
      receiver = Thread.new do
        socket = server.accept
        begin
          socket.read
        rescue Errno::ECONNRESET
          nil
        ensure
          socket.close
        end
      end
      previously_disabled = GC.disable
      expect(sender.request("/info", timeout: 0.1)).to be_internal_error
      expect(receiver.join(1)).to eq(receiver)
    ensure
      GC.enable unless previously_disabled
      receiver&.kill
      receiver&.join(1)
    end

    it "classifies connection refusal before request transmission" do
      sender = client
      server.close
      result = sender.request("/evp_proxy/v4/api/v2/exposures", payload: "{}", timeout: 0.2)
      expect(result).to be_pre_send
      expect(result).to be_internal_error
    end

    it "does not classify accepted-then-closed requests as pre-send" do
      receiver = Thread.new do
        socket = server.accept
        socket.readpartial(4096)
        socket.close
      end
      result = client.request("/evp_proxy/v4/api/v2/exposures", payload: "{}", timeout: 0.2)
      expect(result).to be_internal_error
      expect(result).not_to be_pre_send
    ensure
      receiver&.join(1)
    end

    it "does not drain a delivery response body, even when the server stalls" do
      receiver = Thread.new do
        socket = server.accept
        socket.readpartial(4096)
        socket.write("HTTP/1.1 202 Accepted\r\nContent-Length: 1000000000\r\n\r\n")
        socket.read
        socket.close
      end
      expect(client.request("/evp_proxy/v4/api/v2/exposures", payload: "{}", timeout: 0.2)).to be_ok
      expect(receiver.join(1)).to eq(receiver)
    ensure
      receiver&.kill
      receiver&.join(1)
    end

    it "bounds stalled discovery without retrying" do
      receiver = Thread.new do
        socket = server.accept
        socket.read
        socket.close
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(client.request("/info", timeout: 0.1).info).to be_nil
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    ensure
      receiver&.kill
      receiver&.join(1)
    end
  end
end
