# frozen_string_literal: true

require_relative '../../../core/transport/http/client'

module Datadog
  module DataStreams
    module Transport
      module HTTP
        # HTTP client for Data Streams Monitoring
        class Client < Core::Transport::HTTP::Client
          def send_stats_payload(request)
            send_request(request) do |api, env|
              # TODO how to make api have the derived type for steep?
              api.send_stats(env) # steep:ignore
            end
          end
        end
      end
    end
  end
end
