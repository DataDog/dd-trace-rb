require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'

require 'ddtrace/encoding'
require 'ddtrace/transport'
require 'ddtrace/tracer'
require 'ddtrace/span'

WebMock.allow_net_connect!
WebMock.disable!

# Give access to otherwise private members
module Datadog
  class Writer
    attr_accessor :trace_handler, :service_handler, :worker
  end
  class Tracer
    remove_method :writer
    attr_accessor :writer
  end
  module Workers
    class AsyncTransport
      attr_accessor :transport
    end
  end
  class Context
    remove_method :current_span
    attr_accessor :trace, :sampled, :finished_spans, :current_span
  end
  class Span
    attr_accessor :meta
  end
end

# Return a test tracer instance with a faux writer.
def get_test_tracer
  Datadog::Tracer.new(writer: FauxWriter.new)
end

# Return some test traces
def get_test_traces(n)
  traces = []

  defaults = {
    service: 'test-app',
    resource: '/traces',
    span_type: 'web'
  }

  n.times do
    span1 = Datadog::Span.new(nil, 'client.testing', defaults).finish()
    span2 = Datadog::Span.new(nil, 'client.testing', defaults).finish()
    span2.set_parent(span1)
    traces << [span1, span2]
  end

  traces
end

# Return some test services
def get_test_services
  { 'rest-api' => { 'app' => 'rails', 'app_type' => 'web' },
    'master' => { 'app' => 'postgres', 'app_type' => 'db' } }
end

def get_adapter_name
  adapter_name = ::ActiveRecord::Base.connection_config[:adapter]
  Datadog::Contrib::Rails::Utils.normalize_vendor(adapter_name)
end

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  def initialize
    super(transport: FauxTransport.new(HOSTNAME, PORT))
    @mutex = Mutex.new

    # easy access to registered components
    @spans = []
    @services = {}
  end

  def write(trace, services)
    @mutex.synchronize do
      super(trace, services)
      @spans << trace
      @services = @services.merge(services) unless services.empty?
    end
  end

  def spans(action = :clear)
    @mutex.synchronize do
      spans = @spans
      @spans = [] if action == :clear
      spans.flatten!
      # sort the spans to avoid test flakiness
      spans.sort! do |a, b|
        if a.name == b.name
          if a.resource == b.resource
            if a.start_time == b.start_time
              a.end_time <=> b.end_time
            else
              a.start_time <=> b.start_time
            end
          else
            a.resource <=> b.resource
          end
        else
          a.name <=> b.name
        end
      end
    end
  end

  def trace0_spans
    @mutex.synchronize do
      return [] unless @spans
      return [] if @spans.empty?
      spans = @spans[0]
      @spans = @spans[1..@spans.size]
      spans
    end
  end

  def services
    @mutex.synchronize do
      services = @services
      @services = {}
      services
    end
  end
end

# FauxTransport is a dummy HTTPTransport that doesn't send data to an agent.
class FauxTransport < Datadog::HTTPTransport
  def send(*)
    200 # do nothing, consider it done
  end
end

# SpyTransport is a dummy HTTPTransport that tracks what would be sent.
class SpyTransport < Datadog::HTTPTransport
  attr_reader :helper_sent

  def initialize(hostname, port)
    super(hostname, port)
    @helper_sent = { 200 => {}, 500 => {} }
    @helper_mutex = Mutex.new
    @helper_error_mode = false
    @helper_encoder = Datadog::Encoding::JSONEncoder.new() # easiest to inspect
  end

  def send(endpoint, data)
    data = case endpoint
           when :services
             @helper_encoder.encode_services(data)
           when :traces
             @helper_encoder.encode_traces(data)
           end

    @helper_mutex.synchronize do
      code = @helper_error_mode ? 500 : 200
      @helper_sent[code][endpoint] = [] unless @helper_sent[code].key? endpoint
      @helper_sent[code][endpoint] << data
      return code
    end
  end

  # helper funcs which are not in a normal transport but useful for testing

  # set the error mode, if true, transport returns 500 ERROR, if false, returns 200 OK
  def helper_error_mode!(mode)
    @helper_mutex.synchronize do
      @helper_error_mode = mode ? true : false
    end
  end

  # dumps all the data sent, the data a hash of hashes containing arrays
  # - 1st level hash key is the HTTP code, 200 or 500
  # - 2nd level hash key is the endpoint (eg '/v0.2.traces')
  # - then arrays contain, as a FIFO, all the data passed to send(endpoint, data)
  def helper_dump
    @helper_mutex.synchronize do
      return Marshal.load(Marshal.dump(@helper_sent))
    end
  end
end

# Add class accessors for testing purposes
module Datadog
  class HTTPTransport
    remove_method :traces_endpoint
    remove_method :services_endpoint
    attr_accessor :traces_endpoint, :services_endpoint, :encoder, :headers
  end
end

# update Datadog user configuration; you should pass:
#
# * +key+: the key that should be updated
# * +value+: the value of the key
def update_config(key, value)
  ::Rails.configuration.datadog_trace[key] = value
  config = { config: ::Rails.application.config }
  Datadog::Contrib::Rails::Framework.configure(config)
end

# reset default configuration and replace any dummy tracer
# with the global one
def reset_config
  ::Rails.configuration.datadog_trace = {
    auto_instrument: true,
    auto_instrument_redis: true
  }

  config = { config: ::Rails.application.config }
  Datadog::Contrib::Rails::Framework.configure(config)
end

def test_repeat
  # threading model is different on Java, we need to wait for a longer time
  # (like: be over 10 seconds to make sure handle the case "a flush just happened
  # a few milliseconds ago")
  return 300 if RUBY_PLATFORM == 'java'
  30
end

def try_wait_until(options = {})
  attempts = options.fetch(:attempts, 10)
  backoff = options.fetch(:backoff, 0.1)

  loop do
    break if attempts <= 0 || yield
    sleep(backoff)
    attempts -= 1
  end
end
