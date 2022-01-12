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

Benchmark.ips do |x|
  x.config(time: 30, warmup: 5)

  x.report("#{MODE} tracking", "Object.new")

  x.compare!
end

puts "Total allocations recorded: #{Datadog::Profiling::NativeExtension.allocation_count}"
