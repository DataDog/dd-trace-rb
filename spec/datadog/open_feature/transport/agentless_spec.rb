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
    allow(logger).to receive(:warn)
    allow(Datadog::OpenFeature::Transport::HTTPClient).to receive(:new).and_return(client)
    allow(client).to receive(:request).with("/info", timeout: 5).and_return(response_class.new(code: 200, info: info))
    allow(client).to receive(:request).with(anything, payload: encoded, direct: anything, timeout: 5)
      .and_return(response_class.new(code: 202))
  end

  it "shares one v4 discovery across both signals" do
    transport.send_exposures(payload)
    transport.send_flag_evaluations(payload)
    expect(client).to have_received(:request).with("/info", timeout: 5).once
    %w[exposures flagevaluation].each do |signal|
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/#{signal}",
        payload: encoded, direct: false, timeout: 5).once
    end
  end

  it "uses v2 when it is the only compatible route" do
    info["endpoints"] = ["/evp_proxy/v2/"]
    transport.send_exposures(payload)
    expect(client).to have_received(:request).with("/evp_proxy/v2/api/v2/exposures",
      payload: encoded, direct: false, timeout: 5).once
  end

  [nil, {}, {"endpoints" => ["/evp_proxy/v4"]},
    {"endpoints" => ["/" * 60_000 + "x"], "evp_proxy_allowed_headers" => ["dd-evp-origin", "dd-evp-origin-version"]},
    {"endpoints" => ["/evp_proxy/v4"], "evp_proxy_allowed_headers" => ["DD-EVP-ORIGIN"]},
    {"endpoints" => "/evp_proxy/v4", "evp_proxy_allowed_headers" => "DD-EVP-ORIGIN"}].each do |invalid_info|
    context "with incompatible discovery #{invalid_info.inspect[0, 150]}" do
      let(:info) { invalid_info }

      it "selects sticky direct for both signals" do
        transport.send_exposures(payload)
        transport.send_flag_evaluations(payload)
        expect(client).to have_received(:request).with("/info", timeout: 5).once
        %w[exposures flagevaluation].each do |signal|
          expect(client).to have_received(:request).with("/api/v2/#{signal}",
            payload: encoded, direct: true, timeout: 5).once
        end
      end
    end
  end

  [404, 405, :pre_send].each do |failure|
    it "replays identical encoded bytes once after #{failure} and shares sticky direct" do
      response = (failure == :pre_send) ? response_class.new(pre_send: true) : response_class.new(code: failure)
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 5).and_return(response)
      transport.send_exposures(payload)
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 5).once
      expect(client).to have_received(:request).with("/api/v2/flagevaluation", payload: encoded, direct: true, timeout: 5).once
      expect(client).to have_received(:request).with("/info", timeout: 5).once
    end
  end

  [403, 429, 500, 503, nil].each do |status|
    it "does not replay #{status.inspect}, but switches the sibling writer's future batch" do
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 5).and_return(response_class.new(code: status))
      transport.send_exposures(payload)
      expect(client).not_to have_received(:request).with("/api/v2/exposures", anything)
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/api/v2/flagevaluation", payload: encoded, direct: true, timeout: 5).once
    end
  end

  [301, 302, 307, 400, 401, 408, 422].each do |status|
    it "retains local without replay after #{status}" do
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 5).and_return(response_class.new(code: status))
      transport.send_exposures(payload)
      transport.send_flag_evaluations(payload)
      expect(client).not_to have_received(:request).with("/api/v2/exposures", anything)
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/flagevaluation",
        payload: encoded, direct: false, timeout: 5).once
    end
  end

  it "never retries a direct failure or probes back to local" do
    info["endpoints"] = []
    allow(client).to receive(:request).with("/api/v2/exposures",
      payload: encoded, direct: true, timeout: 5).and_return(response_class.new(pre_send: true))
    2.times { transport.send_exposures(payload) }
    expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 5).twice
    expect(client).to have_received(:request).with("/info", timeout: 5).once
  end

  context "without direct credentials" do
    let(:api_key) { nil }

    [["/evp_proxy/v2/", "/evp_proxy/v4/"], ["/evp_proxy/v2/"]].each do |endpoints|
      context "with an older Agent advertising #{endpoints}" do
        let(:info) { {"endpoints" => endpoints} }

        it "preserves local delivery for both signals without direct credentials" do
          route = endpoints.include?("/evp_proxy/v4/") ? "/evp_proxy/v4" : "/evp_proxy/v2"
          expect(transport.send_exposures(payload)).to be_ok
          expect(transport.send_flag_evaluations(payload)).to be_ok
          %w[exposures flagevaluation].each do |signal|
            expect(client).to have_received(:request).with("#{route}/api/v2/#{signal}",
              payload: encoded, direct: false, timeout: 5).once
          end
          expect(logger).not_to have_received(:warn)
        end
      end
    end

    it "warns once across failed rediscoveries, recovery, and another outage" do
      now = 0.0
      allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
      info["endpoints"] = []
      transport.send_exposures(payload)
      now = 30.0
      transport.send_flag_evaluations(payload)
      now = 60.0
      info["endpoints"] = ["/evp_proxy/v4"]
      expect(transport.send_exposures(payload)).to be_ok
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/flagevaluation", anything)
        .and_return(response_class.new(code: 404))
      transport.send_flag_evaluations(payload)
      expect(logger).to have_received(:warn).with("Feature Flags exposures and flag evaluations are being dropped: " \
        "no usable local Agent EVP route is available, and direct delivery requires DD_API_KEY and a valid DD_SITE.").once
    end

    it "warns immediately when a previously usable local route fails" do
      expect(transport.send_exposures(payload)).to be_ok
      expect(logger).not_to have_received(:warn)
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/flagevaluation", anything)
        .and_return(response_class.new(code: 500))
      transport.send_flag_evaluations(payload)
      expect(logger).to have_received(:warn).once
    end

    it "warns independently in a child process" do
      info["endpoints"] = []
      transport.send_exposures(payload)
      expect_in_fork do
        transport.send_flag_evaluations(payload)
        expect(logger).to have_received(:warn).twice
      end
      expect(logger).to have_received(:warn).once
    end

    it "does not warn when discovery exhausts the shutdown budget" do
      now = 0.0
      allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
      transport.shutdown!(timeout: 5)
      allow(client).to receive(:request).with("/info", timeout: 5) do
        now = 5.0
        response_class.new
      end
      expect(transport.send_exposures(payload)).not_to be_ok
      transport.close
      expect(transport.send_flag_evaluations(payload)).not_to be_ok
      expect(logger).not_to have_received(:warn)
    end

    it "serializes unavailable recovery after a cooldown" do
      now = 0.0
      allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
      info["endpoints"] = []
      4.times.map { Thread.new { transport.send_exposures(payload) } }.each(&:join)
      now = 29.0
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/info", timeout: 5).once
      now = 30.0
      info["endpoints"] = ["/evp_proxy/v4"]
      4.times.map { Thread.new { transport.send_flag_evaluations(payload) } }.each(&:join)
      expect(client).to have_received(:request).with("/info", timeout: 5).twice
      expect(client).to have_received(:request).with("/evp_proxy/v4/api/v2/flagevaluation",
        payload: encoded, direct: false, timeout: 5).exactly(4).times
    end

    [404, 403, 429, 500, nil].each do |status|
      it "enters cooldown after local failure #{status.inspect}" do
        allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
          payload: encoded, direct: false, timeout: 5).and_return(response_class.new(code: status))
        transport.send_exposures(payload)
        expect(transport.send_flag_evaluations(payload)).not_to be_ok
        expect(client).to have_received(:request).exactly(2).times
      end
    end
  end

  it "serializes concurrent initial discovery" do
    selector = transport
    entered = Queue.new
    release = Queue.new
    sibling_started = Queue.new
    first = sibling = nil
    allow(client).to receive(:request).with("/info", timeout: 5) do
      entered << true
      release.pop
      response_class.new(code: 200, info: info)
    end
    first = Thread.new { selector.send_exposures(payload) }
    Timeout.timeout(1) { entered.pop }
    sibling = Thread.new do
      sibling_started << true
      selector.send_flag_evaluations(payload)
    end
    Timeout.timeout(1) do
      sibling_started.pop
      Thread.pass until sibling.status == "sleep" || !sibling.alive?
    end
    expect(client).to have_received(:request).with("/info", timeout: 5).once
    release << true
    expect(first.join(1)).to equal(first)
    expect(sibling.join(1)).to equal(sibling)
    expect(first.value).to be_ok
    expect(sibling.value).to be_ok
    expect(client).to have_received(:request).with("/info", timeout: 5).once
  ensure
    2.times { release << true }
    [first, sibling].compact.each { |sender| sender.kill.join(1) }
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
    expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 5).once
  ensure
    release << true
    sender&.join(1)
  end

  it "resets discovery in a child without reusing the parent's sticky route" do
    transport.send_exposures(payload)
    expect_in_fork do
      transport.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/info", timeout: 5).twice
    end
    expect(client).to have_received(:request).with("/info", timeout: 5).once
  end

  it "preserves child fallback when two writers race to reset after fork" do
    selector = transport
    expect_in_fork do
      entered = Queue.new
      release = Queue.new
      allow(Process).to receive(:pid).and_wrap_original do |original|
        if Thread.current[:pause_fork_reset]
          Thread.current[:pause_fork_reset] = false
          entered << true
          release.pop
        end
        original.call
      end
      allow(client).to receive(:request).with("/evp_proxy/v4/api/v2/flagevaluation", anything)
        .and_return(response_class.new(code: 403))
      delayed = Thread.new do
        Thread.current[:pause_fork_reset] = true
        selector.send_exposures(payload)
      end
      entered.pop
      selector.send_flag_evaluations(payload)
      release << true
      expect(delayed.join(1)).to eq(delayed)
      selector.send_flag_evaluations(payload)
      expect(client).to have_received(:request).with("/info", timeout: 5).once
      expect(client).to have_received(:request).with("/api/v2/exposures", payload: encoded, direct: true, timeout: 5).once
      expect(client).to have_received(:request).with("/api/v2/flagevaluation", payload: encoded, direct: true, timeout: 5).once
    ensure
      release << true
      delayed&.kill
      delayed&.join(1)
    end
  end

  it "discovers in a child while a vanished parent thread held the selector lock" do
    selector = transport
    entered = Queue.new
    release = Queue.new
    allow(client).to receive(:request).with("/info", timeout: 5) do
      entered << true
      release.pop
      response_class.new(code: 200, info: info)
    end
    parent_sender = Thread.new { selector.send_exposures(payload) }
    entered.pop
    expect_in_fork do
      allow(client).to receive(:request).with("/info", timeout: 5).and_return(response_class.new(code: 200, info: info))
      children = [Thread.new { selector.send_exposures(payload) }, Thread.new { selector.send_flag_evaluations(payload) }]
      children.each { |sender| expect(sender.join(1)).to eq(sender) }
      expect(client).to have_received(:request).with("/info", timeout: 5).twice
    ensure
      children.each { |sender| sender.kill.join(1) }
    end
  ensure
    release << true
    parent_sender&.join(1)
    parent_sender&.kill
    parent_sender&.join(1)
  end

  it "keeps a closed selector closed in the child" do
    selector = transport
    selector.close
    expect_in_fork do
      expect(selector.send_exposures(payload)).not_to be_ok
      expect(selector.send_flag_evaluations(payload)).not_to be_ok
      expect(client).not_to have_received(:request)
    end
  end

  it "discards the parent's elapsed shutdown deadline in the child" do
    now = 0.0
    allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
    selector = transport
    selector.shutdown!(timeout: 5)
    now = 6.0
    expect_in_fork do
      expect(selector.send_exposures(payload)).to be_ok
      expect(selector.send_flag_evaluations(payload)).to be_ok
      expect(client).to have_received(:request).with("/info", timeout: 5).once
    end
    expect(selector.send_exposures(payload)).not_to be_ok
  end

  it "retains a shutdown deadline established by the child before its first send" do
    selector = transport
    expect_in_fork do
      now = 0.0
      allow(Datadog::Core::Utils::Time).to receive(:get_time) { now }
      selector.shutdown!(timeout: 0.5)
      now = 0.25
      allow(client).to receive(:request).with("/info", timeout: 0.25).and_return(response_class.new(code: 200, info: info))
      expect(client).to receive(:request).with("/evp_proxy/v4/api/v2/exposures",
        payload: encoded, direct: false, timeout: 0.25).and_return(response_class.new(code: 202))
      expect(selector.send_exposures(payload)).to be_ok
      now = 0.5
      expect(selector.send_flag_evaluations(payload)).not_to be_ok
    end
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
