require "datadog/di/spec_helper"
require 'datadog/di/transport/http'

RSpec.describe Datadog::DI::Transport::Input::Transport do
  di_test

  let(:transport) do
    Datadog::DI::Transport::HTTP.input(agent_settings: agent_settings, logger: logger)
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new
  end

  let(:logger) do
    instance_double(Logger)
  end

  let(:tags) { [] }

  context 'when the combined size of snapshots serialized exceeds intake max' do
    before do
      # Reduce limits to make the test run faster and not require a lot of memory
      stub_const('Datadog::DI::Transport::Input::Transport::DEFAULT_CHUNK_SIZE', 1_000_000)
      stub_const('Datadog::DI::Transport::Input::Transport::MAX_CHUNK_SIZE', 2_000_000)
    end

    let(:snapshot) do
      # It doesn't matter what the payload is, generate a fake one here.
      # This payload serializes to 9781 bytes of JSON.
      1000.times.map do |i|
        [i, i]
      end.to_h
    end

    let(:snapshots) do
      # This serializes to 9782001 bytes of JSON - just under 10 MB.
      [snapshot] * 1_000
    end

    it 'chunks snapshots' do
      # Just under 10 MB payload, default chunk size 1 MB, we expect 10 chunks
      expect(transport).to receive(:send_input_chunk).exactly(10).times do |chunked_payload, serialized_tags|
        expect(chunked_payload.length).to be < 1_000_000
        expect(chunked_payload.length).to be > 800_000
      end
      transport.send_input(snapshots, tags)
    end

    context 'when individual snapshot exceeds intake max' do
      before do
        # Reduce limits even more to force a reasonably-sized snapshot to be dropped
        stub_const('Datadog::DI::Transport::Input::Transport::DEFAULT_CHUNK_SIZE', 1_000)
        stub_const('Datadog::DI::Transport::Input::Transport::MAX_CHUNK_SIZE', 2_000)
      end

      let(:small_snapshot) do
        20.times.map do |i|
          [i, i]
        end.to_h
      end

      let(:snapshots) do
        [small_snapshot, snapshot]
      end

      it 'drops snapshot that is too big' do
        expect(transport).to receive(:send_input_chunk).once do |chunked_payload, serialized_tags|
          expect(chunked_payload.length).to be < 1_000
          expect(chunked_payload.length).to be > 100
        end
        expect_lazy_log(logger, :debug, 'di: dropping too big snapshot')
        transport.send_input(snapshots, tags)
      end
    end
  end
end
