require 'libdatadog'

puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"

require 'securerandom'

def workload
  while true
    SecureRandom.bytes(rand(10000))
    Thread.pass
  end
end

100.times { Thread.new { workload } }

sleep # 60
