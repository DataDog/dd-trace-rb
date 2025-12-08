def clock
  Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
end

Thread.new do
  loop do
    start = clock
    nil while clock < (start + 0.005)
    sleep(0.010)
  end
end

sleep 10
