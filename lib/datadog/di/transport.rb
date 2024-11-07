# frozen_string_literal: true

require_relative 'error'

module Datadog
  module DI
    # Transport for sending probe statuses and snapshots to local agent.
    #
    # Handles encoding of the payloads into multipart posts if necessary,
    # body formatting/encoding, setting correct headers, etc.
    #
    # The transport does not handle batching of statuses or snapshots -
    # the batching should be implemented upstream of this class.
    #
    # Timeout settings are forwarded from agent settings to the Net adapter.
    #
    # The send_* methods raise Error::AgentCommunicationError on errors
    # (network errors and HTTP protocol errors). It is the responsibility
    # of upstream code to rescue these exceptions appropriately to prevent them
    # from being propagated to the application.
    #
    # @api private
    class Transport
      DIAGNOSTICS_PATH = '/debugger/v1/diagnostics'
      INPUT_PATH = '/debugger/v1/input'

      def initialize(agent_settings)
        # Note that this uses host, port, timeout and TLS flag from
        # agent settings.
        @client = Core::Transport::HTTP::Adapters::Net.new(agent_settings)
      end

      def send_diagnostics(payload)
        event_payload = Core::Vendor::Multipart::Post::UploadIO.new(
          StringIO.new(JSON.dump(payload)), 'application/json', 'event.json'
        )
        payload = {'event' => event_payload}
        # Core transport unconditionally specifies headers to underlying
        # Net::HTTP client, ends up passing 'nil' as headers if none are
        # specified by us, which then causes Net::HTTP to die with an exception.
        send_request('Probe status submission',
          path: DIAGNOSTICS_PATH, form: payload, headers: {})
      end

      def send_input(payload)
        send_request('Probe snapshot submission',
          path: INPUT_PATH, body: payload.to_s,
          headers: {'content-type' => 'application/json'},)
      end

      # TODO status should use either input or diagnostics endpoints
      # depending on agent version.
      alias send_status send_diagnostics

      alias send_snapshot send_input

      private

      attr_reader :client

      def send_request(desc, **options)
        # steep:ignore:start
        env = OpenStruct.new(**options)
        # steep:ignore:end
        response = client.post(env)
        unless response.ok?
          raise Error::AgentCommunicationError, "#{desc} failed: #{response.code}: #{response.payload}"
        end
      # Datadog::Core::Transport does not perform any exception mapping,
      # therefore we could have any exception here from failure to parse
      # agent URI for example.
      # If we ever implement retries for network errors, we should distinguish
      # actual network errors from non-network errors that are raised by
      # transport code.
      rescue => exc
        raise Error::AgentCommunicationError, "#{desc} failed: #{exc.class}: #{exc}"
      end
    end
  end
end
