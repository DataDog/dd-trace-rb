# frozen_string_literal: true

require_relative "../input_peeker"
require_relative "../../../instrumentation/gateway/argument"
require_relative "../../../utils/http/url_encoded"
require_relative "../../../../core/header_collection"
require_relative "../../../../tracing/client_ip"

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
              Utils::HTTP::URLEncoded.parse(request.query_string)
            end

            def method
              request.request_method
            end

            def headers
              result = request.env.each_with_object({}) do |(k, v), h|
                h[k.delete_prefix("HTTP_").tap(&:downcase!).tap { |s| s.tr!("_", "-") }] = v if k.start_with?("HTTP_")
              end

              result["content-type"] = request.content_type if request.content_type
              # Since Rack 3.1, content-length is nil if the body is empty, but we still want to send it to the WAF.
              result["content-length"] = request.content_length || "0"
              result
            end

            def url
              request.url
            end

            def fullpath
              request.fullpath
            end

            def path
              request.path
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
              env["REMOTE_ADDR"]
            end

            def form_hash
              # NOTE: Rack populates `rack.request.form_hash` only as a side effect
              #       of {::Rack::Request#POST}, which reads and parses the body.
              request.POST if request.form_data?

              # usually Hash[String, String] but can be a more complex
              # Hash[String, (String|Array|Hash)] when e.g coming from JSON
              env["rack.request.form_hash"]
            rescue => e
              Datadog.logger.debug { "AppSec: Failed to parse request body: #{e.class}: #{e.message}" }
              AppSec.telemetry.report(e, description: "AppSec: Failed to parse request body")

              nil
            end

            # Returns the request body size in bytes using all available methods,
            # or nil when the size cannot be measured within the limit
            #
            # NOTE: The priority of the measurement is the following:
            #       size if it's known, content-length if provided, and buffering
            #       to the limit if unknown-length
            #
            # WARNING: The buffering path adds overhead for streaming web-servers
            #          (Rack 3+) when the body length is unknown
            def body_bytesize(limit)
              io = request.body

              return 0 unless io
              return io.size if io.respond_to?(:size)

              # NOTE: {::Rack::Request#content_length} is a plain `CONTENT_LENGTH`
              #       getter forces no body read
              content_length = request.content_length
              return content_length.to_i if content_length

              # NOTE: A parsed-body cache without a raw byte count means the input
              #       stream was consumed before measurement, consider it unknown-length
              return if env.key?("rack.request.form_hash")

              InputPeeker.peek_bytesize(env, limit: limit)
            end

            # Whether a request body can be collected without forcing a parse:
            # either form data parseable on demand, or a body already parsed upstream
            #
            # NOTE: Rack does not parse JSON itself, a body parser middleware such as
            #       {Rack::JSONBodyParser} populates the form hash read by {#form_hash}
            def collectable_body?
              request.form_data? || request.parseable_data? || env.key?("rack.request.form_hash")
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
