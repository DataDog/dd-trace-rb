def do_alloc(n)
  alloc(n)
end

def alloc(n)
  n.times do
    Object.new
    foo(1)
  end
end

def foo(arg)
  arg + 2
end

# 3.times do
#   Thread.new do
#     while true
#       do_alloc(100_000)
#     end
#   end
# end
# sleep

while true
  do_alloc(100_000)
end
