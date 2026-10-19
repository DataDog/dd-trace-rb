require_relative 'fibonacci'

puts "prof-fibonacci started at #{Time.new.utc}"

FibClient.new.start

run FibServer
