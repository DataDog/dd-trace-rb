# frozen_string_literal: true

# TODO: EK - FIX THIS
require_relative '../../../tracing/transport/request'
require_relative '../../../tracing/transport/parcel'

module Datadog
  module Core
    module Remote
      module Transport
        module Config
          # Data transfer object for encoded traces
          class EncodedParcel
            include Datadog::Tracing::Transport::Parcel

            def count
              data.length
            end
          end

          # Config request
          class Request < Datadog::Tracing::Transport::Request
          end

          # Config response
          module Response
            attr_reader :roots, :targets, :target_files, :client_configs

            def empty?
              @empty
            end
          end

          # Config transport
          class Transport
            attr_reader :client, :apis, :default_api, :current_api_id

            def initialize(apis, default_api)
              @apis = apis

              @client = HTTP::Client.new(current_api)
            end

            ##### there is only one transport! it's negotiation!
            def send_config(payload)
              json = JSON.dump(payload)
              parcel = EncodedParcel.new(json)
              request = Request.new(parcel)

              @client.send_config_payload(request)
            end

            def current_api
              @apis[HTTP::API::V7]
            end
          end
        end
      end
    end
  end
end
