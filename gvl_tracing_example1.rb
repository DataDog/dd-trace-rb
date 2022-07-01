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

2.times.map { Thread.new { fib(27) } }.map(&:join)

Thread.pass

Datadog::Profiling::GvlTracing._native_stop
puts "Stopped!"

gvl_trace = JSON.parse(File.read("gvl_tracing_out.json"))

per_thread_events = Hash.new { |hash, key| hash[key] = [] }

earliest_timestamp = Float::INFINITY
latest_timestamp = -Float::INFINITY

gvl_trace.each do |thread_id, timestamp, event_name|
  next unless thread_id

  earliest_timestamp = timestamp if timestamp < earliest_timestamp
  latest_timestamp = timestamp if timestamp > latest_timestamp

  per_thread_events[thread_id] << [timestamp, event_name]
end

gvl_trace = nil
ux_output = {}

per_thread_events.each do |thread_id, events|
  ux_output[thread_id.to_s] =
    events.each_cons(2).map do |((start_timestamp, start_event), (end_timestamp, _))|
      {
        startNs: start_timestamp,
        endNs: end_timestamp,
        label: start_event,
      }
    end

  last_event_timestamp, last_event = events.last

  if last_event_timestamp < latest_timestamp
    ux_output[thread_id.to_s] <<
      {
        startNs: last_event_timestamp,
        endNs: latest_timestamp,
        label: last_event,
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
