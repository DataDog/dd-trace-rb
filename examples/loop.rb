
require "tracer"




def trace(tracer)
  urls = ["/home", "/login", "/logout"]
  resource = urls.sample()
  tracer.trace("web.request", :service=>"web", :resource=>resource) do
    sleep rand(0..1.0)

    tracer.trace("db.query", :service=>"db") do
      sleep rand(0..1.0)
    end

    tracer.trace("web.template") do
      r = rand(0..1.0)
      if r < 0.25
        1/0
      end
    end
  end
rescue ZeroDivisionError => e
  puts  "error #{e}"
end


tracer = Datadog::Tracer.new()
while true do
  trace(tracer)
  sleep 0.1
  puts 'loop'

end
