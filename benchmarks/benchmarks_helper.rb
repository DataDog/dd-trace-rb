require 'benchmark/ips'
require 'datadog'
require 'pry'

module JobReporter
  def report(name, *args, **opts, &block)
    caller_path = caller_locations.first.path
    prefix = File.basename(caller_path).sub(/_.*\z/, '')
    super("#{prefix} - #{name}", *args, **opts, &block)
  end
end

class Benchmark::IPS::Job
  prepend JobReporter
end
