require 'benchmark/ips'
require 'ddtrace'

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

Benchmark.ips do |x|
  x.config(time: 30, warmup: 5)

  x.report("#{MODE} tracking") do |times|
    Datadog::Profiling::NativeExtension.allocate_many_objects(times)
  end

  x.compare!
end

puts "Total allocations recorded: #{Datadog::Profiling::NativeExtension.allocation_count}"
