require 'ddtrace'
require 'pry'
require 'stackprof'

class ClassA; def initialize; end; end
class ClassB; def initialize; end; end
class ClassC; def initialize; end; end
class ClassD; def initialize; end; end

def main
  #tp = Datadog::Profiling::NativeExtension.start_allocation_tracing
  #tp.enable
  StackProf.start(mode: :object, raw: true)

  ClassA.new
  ClassB.new
  ClassC.new
  ClassD.new
  Set.new

  StackProf.stop
  StackProf.results('stackprof.out')
  #tp.disable

  puts "Got info for #{Datadog::Profiling::NativeExtension.allocation_count} events"

  #res = Datadog::Profiling::NativeExtension.allocation_stacks

  #res.each_with_index { |v, i| puts "i => "; Datadog::Profiling::NativeExtension.debug(v) }

  File.write('test.pprof', Datadog::Profiling::NativeExtension.export_allocation_profile)
  puts "Wrote output to test.pprof"

  binding.pry
end

main
