require('helper')
require('minitest')
require('minitest/autorun')
class UtilsTest < Minitest::Test
  it('rand multithread') do
    n = 100
    mutex = Mutex.new
    @numbers = {}
    threads = []
    n.times do |_i|
      thread = Thread.new do
        r = Datadog::Utils.next_id
        mutex.synchronize { @numbers[r] = true }
      end
      mutex.synchronize { (threads << thread) }
    end
    threads.each(&:join)
    expect(@numbers.length).to(eq(n))
    @numbers = nil
  end
  it('rand no side effect') do
    tracer = get_test_tracer
    srand(1234)
    tracer.trace('random') do
      r1 = rand
      r2 = rand
      expect(r1).to(eq(0.1915194503788923))
      expect(r2).to(eq(0.6221087710398319))
    end
  end
  it('forked process id collision') do
    skip if RUBY_PLATFORM == 'java'
    r, w = IO.pipe
    fork do
      r.close
      w.write(Datadog::Utils.next_id)
      w.close
    end
    w.close
    Process.wait
    expect(r.read.chomp.to_i).to_not(eq(Datadog::Utils.next_id))
    r.close
  end
  it('utf8 encoding happy path') do
    str = 'pristine U+FFE2'.encode(Encoding::UTF_8)
    expect(Datadog::Utils.utf8_encode(str)).to(eq('pristine U+FFE2'))
    expect(Datadog::Utils.utf8_encode(str).encoding).to(eq(::Encoding::UTF_8))
    assert_same(str, Datadog::Utils.utf8_encode(str))
  end
  it('utf8 encoding invalid conversion') do
    time_bomb = "\xC2".force_encoding(::Encoding::ASCII_8BIT)
    expect { time_bomb.encode(Encoding::UTF_8) }.to(raise_error(Encoding::UndefinedConversionError))
    expect(Datadog::Utils.utf8_encode(time_bomb)).to(eq(Datadog::Utils::STRING_PLACEHOLDER))
    expect(Datadog::Utils.utf8_encode(time_bomb, placeholder: '?')).to(eq('?'))
  end
  it('binary data') do
    byte_array = "keep what\xC2 is valid".force_encoding(::Encoding::ASCII_8BIT)
    expect(Datadog::Utils.utf8_encode(byte_array, binary: true)).to(eq('keep what is valid'))
  end
end
