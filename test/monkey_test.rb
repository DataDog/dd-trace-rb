require 'minitest'
require 'minitest/autorun'
require 'ddtrace'

class MonkeyTest < Minitest::Test
  DEFAULT_LOG = Datadog::Logger.log

  def setup
    @buf = StringIO.new
    Datadog::Logger.log = Datadog::Logger.new(@buf)
    Datadog::Logger.log.level = ::Logger::WARN
  end

  def teardown
    Datadog::Logger.log = DEFAULT_LOG
  end

  def assert_warning_issued(method)
    assert_equal(true, Datadog::Logger.log.warn?)
    lines = @buf.string.lines
    assert_equal(6, lines.length, 'there should be 1 log messages (with 6 lines)') if lines.respond_to? :length

    # Test below iterates on lines, this is required for Ruby 1.9 backward compatibility.
    i = 0
    lines.each do |l|
      case i
      when 0
        assert_match(/W,.*WARN -- ddtrace: \[ddtrace\] #{method}/, l)
      when 1
        assert_match(/^\s+Datadog::Monkey has been REMOVED.*/, l)
      end
      i += 1
    end
  end

  def test_registry
    assert_equal(Datadog.registry, Datadog::Monkey.registry)
    assert_warning_issued('Monkey#registry')
  end

  def test_autopatch_modules
    assert_equal({}, Datadog::Monkey.autopatch_modules)
    assert_warning_issued('Monkey#autopatch_modules')
  end

  def test_patch_module
    Datadog::Monkey.patch_module(:rails)
    assert_warning_issued('Monkey#patch_module')
  end

  def test_patch
    Datadog::Monkey.patch([:rails, :rack])
    assert_warning_issued('Monkey#patch')
  end

  def test_get_patched_modules
    assert_equal({}, Datadog::Monkey.get_patched_modules)
    assert_warning_issued('Monkey#get_patched_modules')
  end

  def test_without_warnings
    Datadog::Monkey.without_warnings { nil }
    assert_warning_issued('Monkey#without_warnings')
  end
end
