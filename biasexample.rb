def empty_method # gets 100% blame
end

def slow_method
  x = "h" + "e" + "l" + "l" + "o" + ","
  x += "w" + "o" + "r" + "l" + "d"
  empty_method
end

10000000.times do
  slow_method
end
