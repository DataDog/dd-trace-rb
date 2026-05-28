module BenchmarkMemoryProbe
  module_function

  # Resident set size for the current process, in kilobytes.
  def rss_kb
    `ps -o rss= -p #{Process.pid}`.to_i
  end
end
