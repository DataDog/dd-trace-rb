require 'ddtrace/encoding'
require 'ddtrace/transport'

# SpyTransport is a dummy HTTPTransport that tracks what would be sent.
class SpyTransport < Datadog::HTTPTransport
  attr_reader :helper_sent

  def initialize(hostname, port)
    super(hostname, port)
    @helper_sent = { 200 => {}, 500 => {} }
    @helper_mutex = Mutex.new
    @helper_error_mode = false
    @helper_encoder = Datadog::Encoding::JSONEncoder # easiest to inspect
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
