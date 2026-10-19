# frozen_string_literal: true

require "json"
require "timeout"
require "climate_control"
require "datadog/core"
require "datadog/tracing/span"

class CallbackFailure < Exception; end # rubocop:disable Lint/InheritException

url, interrupt, callback_failure = ARGV
exporter = Datadog::Tracing::Transport::Native::TraceExporter._native_new(
  url: url, tracer_version: nil, language: nil, language_version: nil,
  language_interpreter: nil, hostname: nil, env: nil, service: nil, version: nil,
)
ready_read, ready_write = IO.pipe
release_read, release_write = IO.pipe
reports = []
received = nil
returned = false
failure = RuntimeError.new("original asynchronous interruption")
failure.set_backtrace(["original:1"])
sender = nil

begin
  ClimateControl.modify("OBSERVATION_READY_FD" => ready_write.fileno.to_s,
    "OBSERVATION_RELEASE_FD" => release_read.fileno.to_s) do
    sender = Thread.new do
      span = Datadog::Tracing::Span.new("interrupt.test", id: 2, trace_id: 1)
      exporter._native_send_traces([[span]], false) do |report|
        reports << report
        raise "callback failure" if callback_failure == "standard"
        raise CallbackFailure, "fatal callback failure" if callback_failure == "fatal"
        break :stopped if callback_failure == "break"
      end
      returned = true
    rescue Exception => error # rubocop:disable Lint/RescueException
      received = error
    end
    native = Timeout.timeout(15) { JSON.parse(ready_read.gets) }
    sender.raise(failure) if interrupt == "raise"
    sender.kill if interrupt == "kill"
    release_write.write("x")
    raise "sender did not terminate" unless sender.join(5)
    puts JSON.generate(native: native, reports: reports, returned: returned,
      same_exception: received.equal?(failure), backtrace: received&.backtrace,
      error: received && "#{received.class}: #{received.message}",)
  end
ensure
  release_write.close
  sender&.kill
  exit! 1 if sender && !sender.join(5)
  exporter._native_close
  [ready_read, ready_write, release_read].each(&:close)
end
