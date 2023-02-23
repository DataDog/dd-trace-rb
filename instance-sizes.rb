require 'objspace'

class Potato
  def initialize(a, b)
    @a = a
    @b = b
  end
end

class Salad < Potato
  def initialize(a, b, c, d, e, f, g)
    super(1, 2)
    @c = c
    @d = d
    @e = e
    @f = f
    @g = g
  end
end

Potato.new(1, 2) # Prime anything that needs priming
Salad.new(1, 2, 3, 4, 5, 6, 7)

Datadog::Profiling::Collectors::CpuAndWallTimeWorker.fake_print "=====ALL READY===="

sleep 1

5.times { Potato.new(1, 2) }
5.times { Salad.new(1, 2, 3, 4, 5, 6, 7) }

puts "Ruby Potato size: #{ObjectSpace.memsize_of(Potato.new(1, 2)) }"
puts "Ruby Salad size: #{ObjectSpace.memsize_of(Salad.new(1, 2, 3, 4, 5, 6, 7)) }"

[:a, :b, :c, :d, :e, :f, :g].inspect

Datadog::Profiling::Collectors::CpuAndWallTimeWorker.fake_print "=====DONE ===="

if Datadog::Profiling.respond_to?(:allocation_count)
  puts "Done! -- #{Datadog::Profiling.allocation_count} allocations"
else
  puts "Done!"
end

Datadog.shutdown!

# require 'pry'
# Pry.start
