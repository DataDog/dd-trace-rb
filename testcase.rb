require 'ddtrace'
require 'pry'

class ClassA; def initialize; end; end
class ClassB; def initialize; end; end
class ClassC; def initialize; end; end
class ClassD; def initialize; end; end

def main
  puts "Starting testcase!"
  wip_memory = Datadog::Profiling::WipMemory

  tp = wip_memory.start_allocation_tracing

  ClassA.new
  ClassB.new
  ClassC.new
  ClassD.new
  Set.new

#  tp.disable

  puts "Got info for #{wip_memory.allocation_count} events"

  _start, _finish, pprof_data = wip_memory.current_collector.serialize

  File.write('test.pprof', pprof_data)
  puts "Wrote output to test.pprof"

  #binding.pry
  sleep 10
end

main
