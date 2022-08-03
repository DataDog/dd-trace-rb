# require "gvl-tracing"

def do_alloc(n)
  alloc(n)
end

def alloc(n)
  n.times { Object.new }
end

#GvlTracing.start("gc.json")

while true
  do_alloc(100_000)
  # 3.times.map { Thread.new { do_alloc(100_000) } }.map(&:join)
end
