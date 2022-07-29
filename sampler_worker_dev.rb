require 'ddtrace'
require 'pry'

raise "Profiling broken: #{Datadog::Profiling.unsupported_reason}" unless Datadog::Profiling.supported?

puts "Main thread is #{Thread.main}"

$HACK_RECORDER = stack_recorder = Datadog::Profiling::StackRecorder.new
cpu_and_wall_time_collector = Datadog::Profiling::Collectors::CpuAndWallTime.new(recorder: stack_recorder, max_frames: 400)

sampler_worker = Datadog::Profiling::Collectors::SamplerWorker.new

sampler_worker.start(cpu_and_wall_time_collector: cpu_and_wall_time_collector)

sleep

# while true
#   sleep 0.1
# end

# def run_readline
#   while buf = Readline.readline("> ", true)
#   p buf
#   end
# end

# Thread.new { begin; sleep 0.001; end while true }

# run_readline

# puts "Woke up from readline, sleeping"
# sleep
