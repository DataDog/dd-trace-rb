# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'
require_relative '../../../../core/header_collection'
require_relative '../../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Gateway Request argument. Normalized extration of data from Rack::Request
          class Request < Instrumentation::Gateway::Argument
            attr_reader :env

            def initialize(env)
              super()
              @env = env
            end

            def request
              @request ||= ::Rack::Request.new(env)
            end

            def query
              # Downstream libddwaf expects keys and values to be extractable
              # separately so we can't use [[k, v], ...]. We also want to allow
              # duplicate keys, so we use [{k, v}, ...] instead.
              request.query_string.split('&').map do |e|
                k, v = e.split('=').map { |s| CGI.unescape(s) }

                { k => v }
              end
            end

            def headers
              request.env.each_with_object({}) do |(k, v), h|
                h[k.gsub(/^HTTP_/, '').downcase.tr('_', '-')] = v if k =~ /^HTTP_/
              end
            end

            def body
              request.body.read.tap { request.body.rewind }
            end

            def url
              request.url
            end

            def cookies
              request.cookies
            end

            def host
              request.host
            end

            def user_agent
              request.user_agent
            end

            def remote_addr
              env['REMOTE_ADDR']
            end

            def form_hash
              # force form data processing
              request.POST if request.form_data?

              # usually Hash<String,String> but can be a more complex
              # Hash<String,String||Array||Hash> when e.g coming from JSON
              env['rack.request.form_hash']
            end

            def client_ip
              remote_ip = remote_addr
              header_collection = Datadog::Core::HeaderCollection.from_hash(headers)

              Datadog::Tracing::ClientIp.extract_client_ip(header_collection, remote_ip)
            end
          end
        end
      end
    end
  end
end
