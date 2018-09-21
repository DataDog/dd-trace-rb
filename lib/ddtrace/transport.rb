require 'thread'
require 'net/http'

require 'ddtrace/encoding'
require 'ddtrace/version'
require 'ddtrace/utils'

module Datadog
  # Transport class that handles the spans delivery to the
  # local trace-agent. The class wraps a Net:HTTP instance
  # so that the Transport is thread-safe.
  # rubocop:disable Metrics/ClassLength
  class HTTPTransport
    include Datadog::Utils::InternalTraces
    self.internal_trace_service = 'datadog.transport'.freeze

    attr_accessor :hostname, :port
    attr_reader :traces_endpoint, :services_endpoint

    # seconds before the transport timeout
    TIMEOUT = 1

    # header containing the number of traces in a payload
    TRACE_COUNT_HEADER = 'X-Datadog-Trace-Count'.freeze
    RUBY_INTERPRETER = RUBY_VERSION > '1.9' ? RUBY_ENGINE + '-' + RUBY_PLATFORM : 'ruby-' + RUBY_PLATFORM

    API = {
      V4 = 'v0.4'.freeze => {
        version: V4,
        traces_endpoint: '/v0.4/traces'.freeze,
        services_endpoint: '/v0.4/services'.freeze,
        encoder: Encoding::MsgpackEncoder,
        fallback: 'v0.3'.freeze
      }.freeze,
      V3 = 'v0.3'.freeze => {
        version: V3,
        traces_endpoint: '/v0.3/traces'.freeze,
        services_endpoint: '/v0.3/services'.freeze,
        encoder: Encoding::MsgpackEncoder,
        fallback: 'v0.2'.freeze
      }.freeze,
      V2 = 'v0.2'.freeze => {
        version: V2,
        traces_endpoint: '/v0.2/traces'.freeze,
        services_endpoint: '/v0.2/services'.freeze,
        encoder: Encoding::JSONEncoder
      }.freeze
    }.freeze

    private_constant :API

    CONTENT_TYPE = 'Content-Type'.freeze
    DATADOG_META_LANG = 'Datadog-Meta-Lang'.freeze
    DATADOG_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'.freeze
    DATADOG_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'.freeze
    DATADOG_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'.freeze

    def initialize(hostname, port, options = {})
      api_version = options.fetch(:api_version, V3)

      @hostname = hostname
      @port = port
      @api = API.fetch(api_version)
      @encoder = options[:encoder] || @api[:encoder].new
      @response_callback = options[:response_callback]

      # overwrite the Content-type with the one chosen in the Encoder
      @headers = options.fetch(:headers, {})
      @headers[CONTENT_TYPE] = @encoder.content_type
      @headers[DATADOG_META_LANG] = 'ruby'.freeze
      @headers[DATADOG_META_LANG_VERSION] = RUBY_VERSION
      @headers[DATADOG_META_LANG_INTERPRETER] = RUBY_INTERPRETER
      @headers[DATADOG_META_TRACER_VERSION] = Datadog::VERSION::STRING

      # stats
      @mutex = Mutex.new
      @count_success = 0
      @count_client_error = 0
      @count_server_error = 0
      @count_internal_error = 0
      @count_consecutive_errors = 0
    end

    # route the send to the right endpoint
    def send(endpoint, data)
      internal_span_when(-> { do_trace?(data) }, 'datadog.send'.freeze) do
        case endpoint
        when :services
          status_code = send_services(data)
        when :traces
          status_code = send_traces(data)
        else
          with_active_internal_span { |s| s.set_error(RuntimeError.new("Unsupported endpoint: #{endpoint}")) }

          Datadog::Tracer.log.error("Unsupported endpoint: #{endpoint}")
          return nil
        end

        if downgrade?(status_code)
          internal_child_span('datadog.send.downgrade'.freeze) do
            downgrade!
            send(endpoint, data)
          end
        else
          status_code
        end
      end
    end

    # send data to the trace-agent; the method is thread-safe
    def post(url, data, count = nil)
      begin
        Datadog::Tracer.log.debug("Sending data from process: #{Process.pid}")
        headers = count.nil? ? {} : { TRACE_COUNT_HEADER => count.to_s }
        headers = headers.merge(@headers)
        request = Net::HTTP::Post.new(url, headers)
        request.body = data
        response = Net::HTTP.start(@hostname, @port, read_timeout: TIMEOUT) { |http| http.request(request) }
        handle_response(response)
      rescue StandardError => e
        with_active_internal_span { |s| s.set_error(e) }

        log_error_once(e.message)
        500
      end.tap do
        yield(response) if block_given?
      end
    end

    # Downgrade the connection to a compatibility version of the HTTPTransport;
    # this method should target a stable API that works whatever is the agent
    # or the tracing client versions.
    def downgrade!
      @mutex.synchronize do
        fallback_version = @api.fetch(:fallback)

        @api = API.fetch(fallback_version)
        @encoder = @api[:encoder].new
        @headers[CONTENT_TYPE] = @encoder.content_type
      end
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
      return unless @api[:fallback]

      code == 404 || code == 415
    end

    # handles the server response; here you can log the trace-agent response
    # or do something more complex to recover from a possible error. This
    # function is handled within the HTTP mutex.synchronize so it's thread-safe.
    def handle_response(response)
      status_code = response.code.to_i
      with_active_internal_span { |s| s.set_tag('response.code', status_code) }

      if success?(status_code)
        Datadog::Tracer.log.debug('Payload correctly sent to the trace agent.'.freeze)
        @mutex.synchronize { @count_consecutive_errors = 0 }
        @mutex.synchronize { @count_success += 1 }
      elsif downgrade?(status_code)
        Datadog::Tracer.log.debug("calling the endpoint but received #{status_code}; downgrading the API")
      elsif client_error?(status_code)
        log_error_once("Client error: #{response.message}")
        @mutex.synchronize { @count_client_error += 1 }
      elsif server_error?(status_code)
        log_error_once("Server error: #{response.message}")
      end

      status_code
    rescue StandardError => e
      log_error_once(e.message)
      @mutex.synchronize { @count_internal_error += 1 }
      with_active_internal_span { |s| s.set_error(e) }

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

    private

    def do_trace?(data)
      # Create the span if we already are traced
      return true if Datadog.tracer.active_span
      # Don't trace empty data
      return false unless data

      # over 3 traces means that we most certainly send more than only internal traces
      return true if data.length > 3

      # all spans in all traces shouldn't be only 'datadog.internal' spans
      !data.respond_to?(:all?) || data.all? do |trace|
        !trace.respond_to?(:none?) || trace.none? do |span|
          span.respond_to?(:get_tag) && span.get_tag(Utils::InternalTraces::INTERNAL_TAG)
        end
      end
    end

    def send_traces(data)
      count = data.length

      payload = internal_child_span('datadog.encode.traces'.freeze) do
        with_active_internal_span { |s| s.set_tag('traces.count'.freeze, count) }
        @encoder.encode_traces(data)
      end

      internal_child_span('datadog.traces.post'.freeze) do
        post(@api[:traces_endpoint], payload, count) do |response|
          internal_child_span('datadog.traces.response_callback'.freeze) do
            process_callback(:traces, response)
          end
        end
      end
    end

    def send_services(data)
      payload = internal_child_span('datadog.services.encode'.freeze) do
        @encoder.encode_services(data)
      end

      internal_child_span('datadog.services.post'.freeze) do
        post(@api[:services_endpoint], payload) do |response|
          internal_child_span('datadog.services.response_callback'.freeze) do
            process_callback(:services, response)
          end
        end
      end
    end

    def log_error_once(*args)
      if @count_consecutive_errors > 0
        Datadog::Tracer.log.debug(*args)
      else
        Datadog::Tracer.log.error(*args)
      end

      @mutex.synchronize { @count_consecutive_errors += 1 }
    end

    def process_callback(action, response)
      return unless @response_callback && @response_callback.respond_to?(:call)

      @response_callback.call(action, response, @api)
    rescue => e
      Tracer.log.debug("Error processing callback: #{e}")
    end
  end
end
