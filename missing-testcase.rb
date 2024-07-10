Datadog::Profiling.wait_until_running # Originally was enabled
allocator = Thread.new { loop { BasicObject.new } }
# exceptioner = Thread.new { loop {
#   begin
#     print '.'
#     raise 'Testing...'
#   rescue
#   end
# }}
sleep 1 # originally was 10
allocator.kill; allocator.join
# exceptioner.kill; exceptioner.join
puts "Allocated #{GC.stat(:total_allocated_objects)} objects total"
