require 'libdatadog'
require 'datadog/profiling/load_native_extension'

puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"

require 'securerandom'

def workload
  while true
    SecureRandom.bytes(rand(10000))
    Thread.pass
  end
end

@start = Time.now

Integer(ENV['THREADS'] || 100).times { Thread.new { workload } }

sleep (60*10)

Datadog::Profiling::NativeExtension::Testing._native_malloc_stats
puts "Finished after #{(Time.now - @start).to_f} seconds"
