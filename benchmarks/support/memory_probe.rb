module BenchmarkMemoryProbe
  module_function

  # Resident set size for the current process, in kilobytes. Uses `ps -o rss=`
  # because procfs (/proc/self/status) is Linux-only and getrusage's ru_maxrss
  # has incompatible units across platforms (bytes on macOS, KB on Linux).
  def rss_kb
    `ps -o rss= -p #{Process.pid}`.to_i
  end
end
