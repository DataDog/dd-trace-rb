require 'datadog/core/encoding'
require 'ddtrace/transport/http'

shared_context 'Datadog::Transport::HTTP::Client spy' do
  let(:transport) { instance_double(Datadog::Transport::HTTP::Client) }

  let(:spy_encoder) { Datadog::Core::Encoding::JSONEncoder }
  let(:spy_sent) { { 200 => {}, 500 => {} } }
  let(:spy_error_mode) { false }
  let(:spy_dump) { Marshal.load(Marshal.dump(spy_sent)) }

  before do
    allow(transport).to receive(:send_traces) do |traces|
      data = spy_encoder.encode_traces(traces)

      code = spy_error_mode ? 500 : 200
      spy_sent[code][:traces] = [] unless spy_sent[code].key?(:traces)
      spy_sent[code][:traces] << data

      build_trace_response(code)
    end
  end

  def build_trace_response(code)
    Datadog::Transport::HTTP::Traces::Response.new(
      Datadog::Transport::HTTP::Adapters::Net::Response.new(
        Net::HTTPResponse.new(1.0, code, code.to_s)
      )
    )
  end
end

# SpyTransport is a dummy Datadog::Transport that tracks what would be sent.
class SpyTransport < Datadog::Transport::HTTP::Client
  attr_reader :helper_sent

  def initialize(*)
    @helper_sent = { 200 => {}, 500 => {} }
    @helper_mutex = Mutex.new
    @helper_error_mode = false
    @helper_encoder = Datadog::Core::Encoding::JSONEncoder # easiest to inspect
  end

  def send_traces(data)
    encoded_data = data.map do |trace|
      @helper_encoder.join([Datadog::Transport::Traces::Encoder.encode_trace(@helper_encoder, trace)])
    end

    @helper_mutex.synchronize do
      encoded_data.map do |encoded|
        code = @helper_error_mode ? 500 : 200
        @helper_sent[code][:traces] = [] unless @helper_sent[code].key?(:traces)
        @helper_sent[code][:traces] << encoded
        build_trace_response(code)
      end
    end
  end

  def dump
    Marshal.load(Marshal.dump(@helper_sent))
  end

  def build_trace_response(code)
    Datadog::Transport::HTTP::Traces::Response.new(
      Datadog::Transport::HTTP::Adapters::Net::Response.new(
        Net::HTTPResponse.new(1.0, code, code.to_s)
      ),
      trace_count: 1
    )
  end
end
