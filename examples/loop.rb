require 'ddtrace/tracer'

# Generate a fake trace with the given tracer.
def trace(tracer)
  urls = ['/home', '/login', '/logout']
  resource = urls.sample

  # rake web request.
  tracer.trace('web.request', service: 'web', resource: resource) do
    sleep rand(0..0.1)

    # fake query.
    tracer.trace('db.query', service: 'db') do
      sleep rand(0..0.1)
    end

    # fake template.
    tracer.trace('web.template') do
      r = rand(0..1.0)
      1 / 0 if r < 0.25
    end
  end
rescue ZeroDivisionError => e
  puts "error #{e}"
end

# Generate fake traces.
def run
  tracer = Datadog::Tracer.new
  loop do
    trace(tracer)
    sleep 0.0001
    puts "traced #{tracer.writer.stats}"
  end
end

run if __FILE__ == $PROGRAM_NAME
