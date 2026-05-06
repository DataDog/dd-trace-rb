# frozen_string_literal: true

require 'datadog/symbol_database/transport/http'
require 'datadog/core/vendor/multipart-post/multipart/post/composite_read_io'

# Exercises the real symbol database transport stack against a stubbed agent.
# Verifies that Transport::HTTP.symbols, Transport::Symbols::Request,
# Transport::Symbols::Client, Transport::Symbols::Transport, and
# Transport::HTTP::API::Endpoint construct and dispatch the multipart request
# correctly. Per dd-trace-rb convention, transport classes get direct unit
# tests with the network boundary stubbed (webmock), not by mocking the
# transport stack itself.
RSpec.describe Datadog::SymbolDatabase::Transport::HTTP do
  # Defensively enable WebMock. Other specs in spec:main (notably
  # tracing/integration_spec.rb) call WebMock.disable! in `after` blocks
  # without restoring prior state, leaving WebMock disabled for any later
  # spec that uses stub_request. Without this, our stubs would be no-ops
  # and the transport would hit the real 127.0.0.1:8126 and return ECONNREFUSED.
  before { WebMock.enable! }

  let(:logger) { instance_double(Logger, debug: nil) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.agent.host = '127.0.0.1'
      s.agent.port = 8126
    end
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end

  let(:event_part) do
    Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
      StringIO.new('{"ddsource":"ruby","service":"x","type":"symdb"}'),
      'application/json',
      'event.json',
    )
  end

  let(:file_part) do
    Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
      StringIO.new(Zlib.gzip('{"scopes":[]}')),
      'application/gzip',
      'symbols.json.gz',
    )
  end

  let(:form) { {'event' => event_part, 'file' => file_part} }

  describe '.symbols' do
    subject(:transport) do
      described_class.symbols(agent_settings: agent_settings, logger: logger)
    end

    it 'returns a Transport::Symbols::Transport instance' do
      expect(transport).to be_a(Datadog::SymbolDatabase::Transport::Symbols::Transport)
    end

    it 'wires the multipart Client subclass' do
      expect(transport.client).to be_a(Datadog::SymbolDatabase::Transport::Symbols::Client)
    end

    context 'request dispatch' do
      let(:agent_url) { 'http://127.0.0.1:8126/symdb/v1/input' }

      # WebMock is enabled by the outer `before` block, but spec_helper.rb
      # leaves it disabled by default and other specs in spec:main (notably
      # tracing/integration_spec.rb) call WebMock.disable! in `after` blocks
      # without restoring prior state. Disable WebMock after these dispatch
      # tests to avoid leaking the enabled state into later specs.
      after { WebMock.disable! }

      context 'on a 200 response' do
        before do
          stub_request(:post, agent_url).to_return(status: 200, body: '')
        end

        it 'sends a POST to /symdb/v1/input via the real transport stack' do
          response = transport.send_symbols(form)

          expect(response.code).to eq(200)
          expect(WebMock).to have_requested(:post, agent_url).once
        end

        it 'sends multipart/form-data (Content-Type set by the multipart library)' do
          transport.send_symbols(form)

          expect(WebMock).to have_requested(:post, agent_url)
            .with { |req| req.headers['Content-Type'].to_s.start_with?('multipart/form-data') }
        end
      end

      context 'on a 4xx response' do
        before do
          stub_request(:post, agent_url).to_return(status: 400, body: 'bad request')
        end

        it 'returns a non-error response with the agent status code' do
          response = transport.send_symbols(form)

          expect(response.internal_error?).to be_falsey
          expect(response.code).to eq(400)
        end
      end

      context 'when the agent is unreachable' do
        before do
          stub_request(:post, agent_url).to_raise(Errno::ECONNREFUSED)
        end

        it 'returns an internal error response without raising' do
          response = nil
          expect { response = transport.send_symbols(form) }.not_to raise_error

          expect(response.internal_error?).to be true
        end
      end
    end
  end
end
