require 'ddtrace'
require 'json'
require 'time'
require 'pry'

Datadog::Profiling::GvlTracing._native_start
puts "Started!"

def fib(n)
  return n if n <= 1
  fib(n-1) + fib(n-2)
end

2.times.map { Thread.new { fib(26) } }.map(&:join)

Datadog::Profiling::GvlTracing._native_stop
puts "Stopped!"

gvl_trace = JSON.parse(File.read("gvl_tracing_out.json"))

per_thread_events = Hash.new { |hash, key| hash[key] = [] }

gvl_trace.each do |thread_id, timestamp, event_name|
  next unless thread_id

  per_thread_events[thread_id] << [[timestamp, event_name]]
end

gvl_trace = nil

ux_output = {}

earliest_timestamp = Float::INFINITY
latest_timestamp = -Float::INFINITY

per_thread_events.each do |thread_id, events|
  ux_output[thread_id.to_s] =
    events.each_cons(2).map do |(((start_timestamp, start_event)), ((end_timestamp, _)))|
      earliest_timestamp = start_timestamp if start_timestamp < earliest_timestamp
      latest_timestamp = end_timestamp if end_timestamp > latest_timestamp

      {
        startNs: start_timestamp,
        endNs: end_timestamp,
        label: start_event,
      }
    end
end

File.write(
  "gvl_tracing_ux_#{Time.now.utc.iso8601}.json",
  JSON.pretty_generate(
    threads: ux_output,
    timeRange: {
      startNs: earliest_timestamp,
      endNs: latest_timestamp,
    }
  )
)
