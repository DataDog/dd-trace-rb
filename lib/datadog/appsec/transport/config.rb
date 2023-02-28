# typed: false

require_relative '../../../ddtrace/transport/request'

module Datadog
  module AppSec
    module Transport
      module Config
        # Data transfer object for encoded traces
        class EncodedParcel
          include Datadog::Transport::Parcel

          def initialize(data)
            super(data)
          end

          def count
            data.length
          end
        end

        # Config request
        class Request < Datadog::Transport::Request
        end

        # Config response
        module Response
          attr_reader :roots, :targets, :target_files, :client_configs
        end

        class Transport
          attr_reader :client, :apis, :default_api, :current_api_id

          def initialize(apis, default_api)
            @apis = apis

            @client = HTTP::Client.new(current_api)

            # TODO: this should go in the high level remote config client
            @client_id = SecureRandom.uuid
          end

          ##### there is only one transport! it's negotiation!
          def send_config
            parcel = EncodedParcel.new(json)
            request = Request.new(parcel)

            response = @client.send_config_payload(request)

            # TODO: not sure if we're supposed to do that as we don't chunk like traces
            # Datadog.health_metrics.transport_chunked(responses.size)

            response
          end

          # TODO: this should go in the high level remote config client (except the JSON.dump part)
          def json
            JSON.dump(
              {
                client: {
                  state: {
                    root_version: 1,
                    targets_version: 0, # TODO: should be incremented once applied
                    config_states: [],
                    has_error: false,
                    error: '',
                    backend_client_state: '',
                  },
                  id: @client_id,
                  products: products,
                  is_tracer: true,
                  is_agent: false,
                  client_tracer: {
                    runtime_id: Core::Environment::Identity.id,
                    language: Core::Environment::Identity.lang,
                    tracer_version: Core::Environment::Identity.tracer_version,
                    service: Datadog.configuration.service,
                    env: Datadog.configuration.env,
                    # app_version: app_version, # TODO: I don't know what this is
                    tags: [], # TODO: add nice tags!
                  },
                  # base64 is needed otherwise the Go agent fails with an unmarshal error
                  capabilities: Base64.encode64(capabilities_binary).chomp,
                },
                cached_target_files: [
                    # TODO: to be implemented once we cache these files
                    # {
                    #   path: '',
                    #   length: 0,
                    #   hashes: '';
                    # }
                ],
              }
            )
          end

          # TODO: this is serialization of capabilities, it should go in the request serializer/encoder
          CAP_ASM_ACTIVATION                = 1 << 1 # Remote activation via ASM_FEATURES product
          CAP_ASM_IP_BLOCKING               = 1 << 2 # accept IP blocking data from ASM_DATA product
          CAP_ASM_DD_RULES                  = 1 << 3 # read ASM rules from ASM_DD product
          CAP_ASM_EXCLUSIONS                = 1 << 4 # exclusion filters (passlist) via ASM product
          CAP_ASM_REQUEST_BLOCKING          = 1 << 5 # can block on request info
          CAP_ASM_RESPONSE_BLOCKING         = 1 << 6 # can block on response info
          CAP_ASM_USER_BLOCKING             = 1 << 7 # accept user blocking data from ASM_DATA product
          CAP_ASM_CUSTOM_RULES              = 1 << 8 # accept custom rules
          CAP_ASM_CUSTOM_BLOCKING_RESPONSE  = 1 << 9 # supports custom http code or redirect sa blocking response

          # TODO: this should go in the high level remote config client
          def products
            [
              'ASM_DD',       # Datadog employee issued configuration
              'ASM',          # customer issued configuration (rulesets, passlist...)
              'ASM_FEATURES', # capabilities
              'ASM_DATA',     # config files (IP addresses or users for blocking)
            ]
          end

          # TODO: as a declaration, this should go in the high level remote config client
          # TODO: as serialization, this should go in the request serializer/encoder
          def capabilities
            [
              CAP_ASM_IP_BLOCKING,
              CAP_ASM_USER_BLOCKING,
              CAP_ASM_CUSTOM_RULES,
              CAP_ASM_EXCLUSIONS,
              CAP_ASM_REQUEST_BLOCKING,
              CAP_ASM_RESPONSE_BLOCKING,
              CAP_ASM_DD_RULES,
            ].reduce(&:|)
          end

          # TODO: this is serialization of capabilities, it should go in the request serializer/encoder
          def capabilities_binary
            # TODO: length could be arbitrary
            binding.pry

            # [1] pry(#<Rack::Builder>)> ((1 << 1) | (1 << 2) | (1 << 128)).to_s(16).tap { |s| s.size.odd? && s.prepend('0') }.scan(/\d\d/).map { |e| e.to_i(16) }.pack('C*')
            # => "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x06"
            # [2] pry(#<Rack::Builder>)> Base64.encode64(((1 << 1) | (1 << 2) | (1 << 128)).to_s(16).tap { |s| s.size.odd? && s.prepend('0') }.scan(/\d\d/).map { |e| e.to_i(16) }.pack('C*'))
            # => "AQAAAAAAAAAAAAAAAAAAAAY=\n"

            capabilities.to_s(16).tap { |s| s.size.odd? && s.prepend('0') }.scan(/\h\h/).map { |e| e.to_i(16) }.pack('C*')
          end

          def current_api
            @apis[HTTP::API::V7]
          end
        end
      end
    end
  end
end
