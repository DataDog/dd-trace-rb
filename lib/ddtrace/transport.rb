require 'thread'
require 'net/http'

require 'ddtrace/encoding'
require 'ddtrace/version'

module Datadog
  # Transport class that handles the spans delivery to the
  # local trace-agent. The class wraps a Net:HTTP instance
  # so that the Transport is thread-safe.
  class HTTPTransport
    attr_accessor :hostname, :port
    attr_reader :traces_endpoint, :services_endpoint

    # seconds before the transport timeout
    TIMEOUT = 1

    # header containing the number of traces in a payload
    TRACE_COUNT_HEADER = 'X-Datadog-Trace-Count'.freeze
    RUBY_INTERPRETER = RUBY_VERSION > '1.9' ? RUBY_ENGINE + '-' + RUBY_PLATFORM : 'ruby-' + RUBY_PLATFORM

    def initialize(hostname, port, options = {})
      @hostname = hostname
      @port = port
      @traces_endpoint = '/v0.3/traces'.freeze
      @services_endpoint = '/v0.3/services'.freeze
      @compatibility_mode = false
      @encoder = options.fetch(:encoder, Datadog::Encoding::MsgpackEncoder.new())

      # overwrite the Content-type with the one chosen in the Encoder
      @headers = options.fetch(:headers, {})
      @headers['Content-Type'] = @encoder.content_type
      @headers['Datadog-Meta-Lang'] = 'ruby'
      @headers['Datadog-Meta-Lang-Version'] = RUBY_VERSION
      @headers['Datadog-Meta-Lang-Interpreter'] = RUBY_INTERPRETER
      @headers['Datadog-Meta-Tracer-Version'] = Datadog::VERSION::STRING

      # stats
      @mutex = Mutex.new
      @count_success = 0
      @count_client_error = 0
      @count_server_error = 0
      @count_internal_error = 0
    end

    # route the send to the right endpoint
    def send(endpoint, data)
      case endpoint
      when :services
        payload = @encoder.encode_services(data)
        status_code = post(@services_endpoint, payload)
      when :traces
        count = data.length
        payload = @encoder.encode_traces(data)
        status_code = post(@traces_endpoint, payload, count)
      else
        Datadog::Tracer.log.error("Unsupported endpoint: #{endpoint}")
        return nil
      end

      return status_code unless downgrade?(status_code) && !@compatibility_mode

      # the API endpoint is not available so we should downgrade the connection and re-try the call
      downgrade!
      send(endpoint, data)
    end

    # send data to the trace-agent; the method is thread-safe
    def post(url, data, count = nil)
      Datadog::Tracer.log.debug("Sending data from process: #{Process.pid}")
      headers = count.nil? ? {} : { TRACE_COUNT_HEADER => count.to_s }
      headers = headers.merge(@headers)
      request = Net::HTTP::Post.new(url, headers)
      request.body = data

      response = Net::HTTP.start(@hostname, @port, read_timeout: TIMEOUT) { |http| http.request(request) }
      handle_response(response)
    rescue StandardError => e
      Datadog::Tracer.log.error(e.message)
      500
    end

    # Downgrade the connection to a compatibility version of the HTTPTransport;
    # this method should target a stable API that works whatever is the agent
    # or the tracing client versions.
    def downgrade!
      @compatibility_mode = true
      @traces_endpoint = '/v0.2/traces'.freeze
      @services_endpoint = '/v0.2/services'.freeze
      @encoder = Datadog::Encoding::JSONEncoder.new()
      @headers['Content-Type'] = @encoder.content_type
    end

    def informational?(code)
      code.between?(100, 199)
    end

    def success?(code)
      code.between?(200, 299)
    end

    def redirect?(code)
      code.between?(300, 399)
    end

    def client_error?(code)
      code.between?(400, 499)
    end

    def server_error?(code)
      code.between?(500, 599)
    end

    # receiving a 404 means that we're targeting an endpoint that is not available
    # in the trace agent. Usually this means that we've an up-to-date tracing client,
    # while running an obsolete agent.
    # receiving a 415 means that we're using an unsupported content-type with an existing
    # endpoint. Usually this means that we're using a newer encoder with a previous
    # endpoint. In both cases, we're going to downgrade the transporter encoder so that
    # it will target a stable API.
    def downgrade?(code)
      code == 404 || code == 415
    end

    # handles the server response; here you can log the trace-agent response
    # or do something more complex to recover from a possible error. This
    # function is handled within the HTTP mutex.synchronize so it's thread-safe.
    def handle_response(response)
      status_code = response.code.to_i

      if success?(status_code)
        Datadog::Tracer.log.debug('Payload correctly sent to the trace agent.')
        @mutex.synchronize { @count_success += 1 }
      elsif downgrade?(status_code)
        Datadog::Tracer.log.debug("calling the endpoint but received #{status_code}; downgrading the API")
      elsif client_error?(status_code)
        Datadog::Tracer.log.error("Client error: #{response.message}")
        @mutex.synchronize { @count_client_error += 1 }
      elsif server_error?(status_code)
        Datadog::Tracer.log.error("Server error: #{response.message}")
        @mutex.synchronize { @count_server_error += 1 }
      end

      status_code
    rescue StandardError => e
      Datadog::Tracer.log.error(e.message)
      @mutex.synchronize { @count_internal_error += 1 }
      500
    end

    def stats
      @mutex.synchronize do
        {
          success: @count_success,
          client_error: @count_client_error,
          server_error: @count_server_error,
          internal_error: @count_internal_error
        }
      end
    end
  end
end
