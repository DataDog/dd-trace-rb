require_relative 'support/boot'

# This benchmark measures the performance of allocation profiling

class ExportToFile
  PPROF_PREFIX = ENV.fetch('DD_PROFILING_PPROF_PREFIX', 'profiler-allocation')

  def export(flush)
    File.write("#{PPROF_PREFIX}#{flush.start.strftime('%Y%m%dT%H%M%SZ')}.pprof", flush.pprof_data)
    true
  end
end

Benchmarker.define do
  benchmark 'Allocations (baseline)' do
    BasicObject.new
  end
end

Benchmarker.define do
  before do
    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = true
      c.profiling.advanced.gc_enabled = false
      c.profiling.exporter.transport = ExportToFile.new unless VALIDATE_BENCHMARK_MODE
    end
    Datadog::Profiling.wait_until_running

    3.times { GC.start }
  end

  benchmark "Allocations (#{ENV['CONFIG']})" do
    BasicObject.new
  end
end
