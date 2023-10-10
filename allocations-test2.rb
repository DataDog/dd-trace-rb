class ObjectPerSecondAllocator
  def initialize(objects_per_second:, seconds_to_run:)
    @objects_per_second = objects_per_second
    @seconds_to_run = seconds_to_run
  end

  def run
    sleep_between_allocations = 1.0 / @objects_per_second

    puts "Allocating #{@objects_per_second} objects per second over #{@seconds_to_run} seconds"

    @seconds_to_run.times do
      @objects_per_second.times do
        Object.allocate
        sleep(sleep_between_allocations)
      end
      puts "--- ~1 second elapsed --- (Allocating #{@objects_per_second} objects per second over #{@seconds_to_run} seconds)"
    end
  end
end

ObjectPerSecondAllocator.new(objects_per_second: 1_000, seconds_to_run: 3).run
ObjectPerSecondAllocator.new(objects_per_second: 10, seconds_to_run: 3).run
ObjectPerSecondAllocator.new(objects_per_second: 10_000, seconds_to_run: 3).run

puts "Finished test!"
