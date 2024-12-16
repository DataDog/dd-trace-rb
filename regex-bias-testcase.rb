require 'benchmark/ips'
require 'ostruct'

pre_compiled = Regexp.new("/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/")
empty_string = ""
A_TIMES_ONE_HUNDRED = "a" * 100
A_TIMES_ONE_HUNDRED_PLUS_B =  A_TIMES_ONE_HUNDRED + "b"

def get_a_times_onehundred
  A_TIMES_ONE_HUNDRED
end

def get_a_times_onehundred_plus_b
  A_TIMES_ONE_HUNDRED_PLUS_B
end

Benchmark.ips do |x|
  x.config(time: 10, warmup: 0)

  x.report('regex not precompiled') do
    res = /#{"^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$"}#{empty_string}/.match(get_a_times_onehundred)
    res = /#{"^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$"}#{empty_string}/.match(get_a_times_onehundred_plus_b)
  end

  x.report('regex precompiled') do
    res = pre_compiled.match(get_a_times_onehundred)
    res = pre_compiled.match(get_a_times_onehundred_plus_b)
  end

  x.compare!
end
