require 'benchmark/ips'
require 'ddtrace'

puts RUBY_DESCRIPTION

MODE = ENV['MODE']

if MODE == 'no'
  # do nothing
elsif MODE == 'with'
  # enable tracking
  tp = Datadog::Profiling::NativeExtension.start_allocation_tracing
  tp.enable
  puts "Allocation tracking enabled"
else
  raise "Please specify MODE environment variable as 'with' or 'no'"
end

puts "Warmup..."

Datadog::Profiling::NativeExtension.allocate_many_objects(500_000)

puts "Running..."

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

Datadog::Profiling::NativeExtension.allocate_many_objects(20_000_000)

finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start

puts "Total time: #{finish / 1_000_000_000.0}"

puts "Total allocations recorded: #{Datadog::Profiling::NativeExtension.allocation_count}"
