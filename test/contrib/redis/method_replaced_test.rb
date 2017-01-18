
require 'contrib/redis/test_helper'
require 'helper'

class RedisMethodReplacedTest < Minitest::Test
  # We want to make sure that the patcher works even when the patched methods
  # have already been replaced by another library.

  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379

  def setup
    ::Redis::Client.class_eval do
      alias_method :call_original, :call
      remove_method :call
      def call(*args, &block)
        @datadog_test_called ||= false
        if @datadog_test_called
          raise Minitest::Assertion, 'patched methods called in infinite loop'
        end
        @datadog_test_called = true

        call_original(*args, &block)
      end
    end
  end

  def test_main
    redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)
    redis.call(['ping', 'hello world'])
  end

  def teardown
    ::Redis::Client.class_eval do
      remove_method :call
      alias_method :call, :call_original
      remove_method :call_original
    end
  end
end
