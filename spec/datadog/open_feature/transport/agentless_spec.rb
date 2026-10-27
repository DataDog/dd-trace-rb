# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/transport/agentless"

RSpec.describe Datadog::OpenFeature::Transport::Agentless do
  subject(:transport) do
    described_class.new(agent_settings: agent_settings, site: "datadoghq.com", api_key: api_key, logger: logger)
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(Datadog.configuration) }
  let(:logger) { logger_allowing_debug }
  let(:api_key) { "test-api-key" }
  let(:client) { instance_double(Datadog::OpenFeature::Transport::HTTPClient, direct?: !api_key.nil?) }
  let(:response_class) { Datadog::OpenFeature::Transport::Response }
  let(:info) do
    {"endpoints" => ["/evp_proxy/v2", "/evp_proxy/v4"],
     "evp_proxy_allowed_headers" => ["dd-evp-origin", "DD-EVP-ORIGIN-VERSION"]}
  end
  let(:payload) { {"events" => [{"flag" => "test"}]} }
  let(:encoded) { Datadog::Core::Encoding::JSONEncoder.encode(payload) }

  before do
    allow(Datadog::OpenFeature::Transport::HTTPClient).to receive(:new).and_return(client)
    allow(client).to receive(:request).with("/info", timeout: 1).and_return(response_class.new(code: 200, info: info))
    allow(client).to receive(:request).with(anything, payload: encoded, direct: anything, timeout: 2)
      .and_return(response_class.new(code: 202))
  end

  it "shares one v4 discovery across both signals" do
    transport.send_exposures(payload)
    transport.send_flag_evaluations(payload)
    expect(client).to have_received(:request).with("/info", timeout: 1).once
    %w[exposures flagevaluation].each do |signal|
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/#{signal}",
        payload: encoded, direct: false, timeout: 2).once
    end
  end

  it "uses v2 when it is the only compatible route" do
    info["endpoints"] = ["/evp_proxy/v2"]
    transport.send_exposures(payload)
    expect(client).to have_received(:request).with("/evp_proxy/v2/api/v2/exposures",
      payload: encoded, direct: false, timeout: 2).once
  end

  [nil, {}, {"endpoints" => ["/evp_proxy/v4"]},
    {"endpoints" => ["/evp_proxy/v4"], "evp_proxy_allowed_headers" => ["DD-EVP-ORIGIN"]},
    {"endpoints" => "/evp_proxy/v4", "evp_proxy_allowed_headers" => "DD-EVP-ORIGIN"}].each do |invalid_info|
    context "with incompatible discovery #{invalid_info.inspect}" do
      let(:info) { invalid_info }

      it "selects sticky direct for both signals" do
        transport.send_exposures(payload)
        transport.send_flag_evaluations(payload)
        expect(client).to have_received(:request).with("/info", timeout: 1).once
        %w[exposures flagevaluation].each do |signal|
          expect(client).to have_received(:request).with("/api/v2/#{signal}",
            payload: encoded, direct: true, timeout: 2).once
        end
      end
    end
  end

  [404, 405, :pre_send].each do |failure|
    it "replays identical encoded bytes once after #{failure} and shares sticky direct" do
      response = (failure == :pre_send) ? response_class.new(pre_send: true) : response_class.new(code: failure)
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 2).and_return(response)
      transport.send_exposures(payload)
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 2).once
      expect(client).to have_received(:request).with("/api/v2/flagevaluation", payload: encoded, direct: true, timeout: 2).once
      expect(client).to have_received(:request).with("/info", timeout: 1).once
    end
  end

  [403, 429, 500, 503, nil].each do |status|
    it "does not replay #{status.inspect}, but switches the sibling writer's future batch" do
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 2).and_return(response_class.new(code: status))
      transport.send_exposures(payload)
      expect(client).not_to have_received(:request).with("/api/v2/exposures", anything)
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/api/v2/flagevaluation", payload: encoded, direct: true, timeout: 2).once
    end
  end

  [301, 302, 307, 400, 401, 408, 422].each do |status|
    it "retains local without replay after #{status}" do
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 2).and_return(response_class.new(code: status))
      transport.send_exposures(payload)
      transport.send_flag_evaluations(payload)
      expect(client).not_to have_received(:request).with("/api/v2/exposures", anything)
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/flagevaluation",
        payload: encoded, direct: false, timeout: 2).once
    end
  end

  it "never retries a direct failure or probes back to local" do
    info["endpoints"] = []
    allow(client).to receive(:request).with("/api/v2/exposures",
      payload: encoded, direct: true, timeout: 2).and_return(response_class.new(pre_send: true))
    2.times { transport.send_exposures(payload) }
    expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 2).twice
    expect(client).to have_received(:request).with("/info", timeout: 1).once
  end

  context "without direct credentials" do
    let(:api_key) { nil }

    it "serializes unavailable recovery after a cooldown" do
      now = 0.0
      allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
      info["endpoints"] = []
      4.times.map { Thread.new { transport.send_exposures(payload) } }.each(&:join)
      now = 29.0
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/info", timeout: 1).once
      now = 30.0
      info["endpoints"] = ["/evp_proxy/v4"]
      4.times.map { Thread.new { transport.send_flag_evaluations(payload) } }.each(&:join)
      expect(client).to have_received(:request).with("/info", timeout: 1).twice
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/flagevaluation",
        payload: encoded, direct: false, timeout: 2).exactly(4).times
    end

    [404, 403, 429, 500, nil].each do |status|
      it "enters cooldown after local failure #{status.inspect}" do
        allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
          payload: encoded, direct: false, timeout: 2).and_return(response_class.new(code: status))
        transport.send_exposures(payload)
        expect(transport.send_flag_evaluations(payload)).not_to be_ok
        expect(client).to have_received(:request).exactly(2).times
      end
    end
  end

  it "serializes concurrent initial discovery" do
    selector = transport
    8.times.map { Thread.new { selector.send_exposures(payload) } }.each(&:join)
    expect(client).to have_received(:request).with("/info", timeout: 1).once
  end

  it "does not let an in-flight success restore local after a sibling falls back" do
    entered = Queue.new
    release = Queue.new
    allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures", anything) do
      entered << true
      release.pop
      response_class.new(code: 202)
    end
    allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/flagevaluation", anything)
      .and_return(response_class.new(code: 404))
    sender = Thread.new { transport.send_exposures(payload) }
    entered.pop
    transport.send_flag_evaluations(payload)
    release << true
    sender.join
    transport.send_exposures(payload)
    expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 2).once
  ensure
    release << true
    sender&.join(1)
  end

  it "resets discovery in a child without reusing the parent's sticky route" do
    transport.send_exposures(payload)
    expect_in_fork do
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/info", timeout: 1).twice
    end
    expect(client).to have_received(:request).with("/info", timeout: 1).once
  end

  it "bounds final sends by the remaining shutdown budget and closes delivery" do
    now = 0.0
    allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
    transport.shutdown!(timeout: 5)
    now = 4.5
    allow(client).to receive(:request).with("/info", timeout: 0.5).and_return(response_class.new(info: info))
    expect(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
      payload: encoded, direct: false, timeout: 0.5).and_return(response_class.new(code: 202))
    transport.send_exposures(payload)
    transport.close
    expect(transport.send_flag_evaluations(payload)).not_to be_ok
  end
end
