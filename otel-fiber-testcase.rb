puts "CURRENT FIBER: #{Fiber.current}"

Fiber.attr_accessor :opentelemetry_context

Fiber.current.opentelemetry_context = 1234

sleep 0.5

fiber = Fiber.new do
  puts "CURRENT FIBER: #{Fiber.current}"

  Fiber.current.opentelemetry_context = 5678

  sleep 0.5
end

fiber.resume

puts "DONE!"
