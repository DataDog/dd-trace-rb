# frozen_string_literal: true

require 'json'

require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative '../../core/transport/transport'
require_relative 'http/diagnostics'

module Datadog
  module DI
    module Transport
      module Diagnostics
        class EncodedParcel
          include Datadog::Core::Transport::Parcel
        end

        class Request < Datadog::Core::Transport::Request
        end

        class Transport < Core::Transport::Transport
          def send_diagnostics(payload)
            # TODO use transport encoder functionality?
            json = JSON.dump(payload)
            parcel = EncodedParcel.new(json)
            request = Request.new(parcel)

            response = @client.send_request(:diagnostics, request)
            unless response.ok?
              # TODO Datadog::Core::Transport::InternalErrorResponse
              # does not have +code+ method, what is the actual API of
              # these response objects?
              raise Error::AgentCommunicationError, "send_diagnostics failed: #{begin
                response.code
              rescue
                "???"
              end}: #{response.payload}"
            end
          rescue Error::AgentCommunicationError
            raise
          # Datadog::Core::Transport does not perform any exception mapping,
          # therefore we could have any exception here from failure to parse
          # agent URI for example.
          # If we ever implement retries for network errors, we should distinguish
          # actual network errors from non-network errors that are raised by
          # transport code.
          rescue => exc
            raise Error::AgentCommunicationError, "send_diagnostics failed: #{exc.class}: #{exc}"
          end
        end
      end
    end
  end
end
