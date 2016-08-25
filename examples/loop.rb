
require "tracer"

tracer = Datadog::Tracer.new()


urls = ["/home", "/login", "/logout"]

while true do

  resource = urls.sample()
  tracer.trace("web.request", :service=>"web", :resource=>resource) do
    sleep rand(0..1.0)

    tracer.trace("db.query", :service=>"db") do
      sleep rand(0..1.0)
    end

    tracer.trace("web.template") do
      sleep rand(0..1.0)
    end
  end

  puts 'loop'

end
