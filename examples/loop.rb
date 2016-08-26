
require "tracer"

# Generate a fake trace with the given tracer.
def trace(tracer)
  urls = ["/home", "/login", "/logout"]
  resource = urls.sample()

  # rake web request.
  tracer.trace("web.request", :service=>"web", :resource=>resource) do
    sleep rand(0..1.0)

    # fake query.
    tracer.trace("db.query", :service=>"db") do
      sleep rand(0..1.0)
    end

    # fake template.
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

# Generate fake traces.
def run()
  tracer = Datadog::Tracer.new()
  loop do
    trace(tracer)
    sleep 0.1
    puts 'loop'
  end
end


if __FILE__ == $0
  run()
end
