require 'helper'

require 'minitest'
require 'minitest/autorun'

class UtilsTest < Minitest::Test
  def test_rand_multithread
    n = 100

    mutex = Mutex.new

    @numbers = {}
    threads = []
    n.times do |_i|
      thread = Thread.new do
        r = Datadog::Utils.next_id()
        mutex.synchronize do
          @numbers[r] = true
        end
      end
      mutex.synchronize do
        threads << thread
      end
    end
    threads.each(&:join)
    assert_equal(n, @numbers.length, 'each trace ID should be picked only once')
    @numbers = nil
  end

  def test_rand_no_side_effect
    tracer = get_test_tracer()

    srand 1234
    tracer.trace('random') do # this creates span, so calls our PRNG
      r1 = rand
      r2 = rand
      # Should we not use our own PRNG, the test below would fail, typically
      # r1 would be 0.6221087710398319 because its expected values has been
      # picked up already and used for the span_id & trace_id.
      assert_equal(0.1915194503788923, r1, '1st randomly generated number should not be altered by tracing')
      assert_equal(0.6221087710398319, r2, '2nd randomly generated number should not be altered by tracing')
    end
  end

  def test_forked_process_id_collision
    skip if RUBY_PLATFORM == 'java'

    r, w = IO.pipe

    fork do
      r.close
      w.write(Datadog::Utils.next_id)
      w.close
    end

    w.close
    Process.wait
    refute_equal(Datadog::Utils.next_id, r.read.chomp.to_i)
    r.close
  end

  def test_utf8_encoding_happy_path
    # we can't use utf-8 literals because our tests run against ruby 1.9.3
    str = 'pristine ￢'.encode(Encoding::UTF_8)

    assert_equal('pristine ￢', Datadog::Utils.utf8_encode(str))

    assert_equal(::Encoding::UTF_8, Datadog::Utils.utf8_encode(str).encoding)

    # we don't allocate new objects when a valid UTF-8 string is provided
    assert_same(str, Datadog::Utils.utf8_encode(str))
  end

  def test_utf8_encoding_invalid_conversion
    time_bomb = "\xC2".force_encoding(::Encoding::ASCII_8BIT)

    # making sure this is indeed a problem
    assert_raises(Encoding::UndefinedConversionError) do
      time_bomb.encode(Encoding::UTF_8)
    end

    assert_equal(Datadog::Utils::EMPTY_STRING, Datadog::Utils.utf8_encode(time_bomb))

    # we can also set a custom placeholder
    assert_equal('?', Datadog::Utils.utf8_encode(time_bomb, placeholder: '?'))
  end

  def test_binary_data
    byte_array = "keep what\xC2 is valid".force_encoding(::Encoding::ASCII_8BIT)

    assert_equal('keep what is valid', Datadog::Utils.utf8_encode(byte_array, binary: true))
  end
end
