require "benchmark/ips"

module JobReporter
  def report(name, ...)
    caller_path = caller_locations(1..1).first.path
    prefix = File.basename(caller_path).sub(/_.*\z/, "")
    super("#{prefix} - #{name}", ...)
  end
end

class Benchmark::IPS::Job
  prepend JobReporter
end
