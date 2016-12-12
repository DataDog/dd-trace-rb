require 'ddtrace/contrib/redis/quantize'
require 'contrib/redis/test_helper'
require 'helper'

class Unstringable
  def to_s
    raise "can't make a string of me"
  end
end

class RedisQuantizeTest < Minitest::Test
  def test_format_arg
    expected = { '' => '',
                 'HGETALL' => 'HGETALL',
                 'A' * 100 => 'A' * 100,
                 'B' * 101 => 'B' * 97 + '...',
                 'C' * 1000 => 'C' * 97 + '...',
                 nil => '',
                 Unstringable.new => '?' }
    expected.each do |k, v|
      assert_equal(v, Datadog::Contrib::Redis::Quantize.format_arg(k))
    end
  end

  def test_format_command_args
    assert_equal('SET KEY VALUE', Datadog::Contrib::Redis::Quantize.format_command_args(%w(SET KEY VALUE)))
    command_args = []
    20.times { command_args << ('X' * 90) }
    trimmed = Datadog::Contrib::Redis::Quantize.format_command_args(command_args)
    assert_equal(1000, trimmed.length)
    assert_equal('X...', trimmed[996..999])
  end
end
