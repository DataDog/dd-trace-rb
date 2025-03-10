require 'datadog'

recorder = Datadog::Profiling::StackRecorder.for_testing(heap_samples_enabled: true)

def current_rss
  # `ps` outputs RSS in kilobytes for the given PID
  pid = Process.pid
  rss = `ps -o rss= -p #{pid}`.strip.to_i
  rss
end

def print_rss(step) = puts "#{step}: Rss is #{current_rss}"


print_rss("start")

10_000_000.times do |i|
  GC.start if i % 1000 == 0
  Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(recorder, rand().to_s, 1, false)
end

print_rss("after 100_000 intern")
sleep 5

recorder = nil
10.times { GC.start }

print_rss("after GC")
puts Datadog::Profiling::NativeExtension::Testing._native_malloc_stats
print_rss("after trim")

sleep
