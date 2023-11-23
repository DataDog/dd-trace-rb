begin
  Process.detach(fork { exit! }).instance_variable_get(:@foo)
rescue SystemStackError => e
  puts "Got SystemStackError"
  puts e.inspect
end

puts "Sleeping forever"
sleep
