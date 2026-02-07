require_relative '../spec_helper'

RSpec.describe Datadog::DataStreams::Transport do
  before do
    skip_if_data_streams_not_supported(self)
  end

  let(:logger) { logger_allowing_debug }
  let(:settings) do
    double('Settings',
      service: Datadog.configuration.service,
      env: Datadog.configuration.env,)
  end
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettings.new(
      adapter: :net_http, hostname: 'localhost', port: http_server_port
    )
  end
  let(:processor) { Datadog::DataStreams::Processor.new(interval: 10.0, logger: logger, settings: settings, agent_settings: agent_settings) }

  let(:received_requests) { [] }

  http_server do |http_server|
    http_server.mount_proc('/v0.1/pipeline_stats') do |req, res|
      received_requests << req
    end
  end

  it 'sets the expected headers' do
    # DSM does not implemement a flush method of its own and also
    # does not use the Queue worker module, which provides a flush method.
    # The simplest way to invoke the transport layer is to request a
    # payload to be sent directly.
    processor.send(:worker).terminate
    processor.send(:process_kafka_consume_event,
      topic: 'topic',
      partition: 0,
      offset: 0,
      timestamp: Time.now,
      timestamp_sec: 1,)
    processor.send(:flush_stats)
    expect(received_requests.length).to be 1
    req = received_requests.first
    expect(req.path).to eq('/v0.1/pipeline_stats')
    headers = req.header.transform_keys(&:downcase).transform_values(&:first)
    expect(headers).to include(
      'content-type' => 'application/msgpack',
      'content-encoding' => 'gzip',
    )
    expect(headers).to include(Datadog::Core::Transport::HTTP.default_headers.transform_keys(&:downcase))
  end
end
