require 'ddtrace'
require 'pry'

class ClassA; def initialize; end; end
class ClassB; def initialize; end; end
class ClassC; def initialize; end; end
class ClassD; def initialize; end; end

def main
  tp = Datadog::Profiling::NativeExtension.start_allocation_tracing

  ClassA.new
  ClassB.new
  ClassC.new
  ClassD.new
  Set.new

  tp.disable

  puts "Got info for #{Datadog::Profiling::NativeExtension.allocation_count} events"

  # File.write('test.pprof', Datadog::Profiling::NativeExtension.export_allocation_profile)
  # puts "Wrote output to test.pprof"

  #binding.pry
  sleep 10
end

main
