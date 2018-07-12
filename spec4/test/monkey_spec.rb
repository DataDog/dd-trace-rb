require('minitest')
require('minitest/autorun')
require('ddtrace')
class MonkeyTest < Minitest::Test
  DEFAULT_LOG = Datadog::Tracer.log
  before do
    @buf = StringIO.new
    Datadog::Tracer.log = Datadog::Logger.new(@buf)
    Datadog::Tracer.log.level = ::Logger::WARN
  end
  after { Datadog::Tracer.log = DEFAULT_LOG }
  def assert_warning_issued(method)
    assert_equal(true, Datadog::Tracer.log.warn?)
    lines = @buf.string.lines
    if lines.respond_to?(:length)
      assert_equal(6, lines.length, 'there should be 1 log messages (with 6 lines)')
    end
    i = 0
    lines.each do |l|
      case i
      when 0 then
        assert_match(/W,.*WARN -- ddtrace: \[ddtrace\] #{method}/, l)
      when 1 then
        assert_match(/^\s+Datadog::Monkey has been REMOVED.*/, l)
      end
      i = (i + 1)
    end
  end
  it('registry') do
    expect(Datadog::Monkey.registry).to(eq(Datadog.registry))
    assert_warning_issued('Monkey#registry')
  end
  it('autopatch modules') do
    expect(Datadog::Monkey.autopatch_modules).to(eq({}))
    assert_warning_issued('Monkey#autopatch_modules')
  end
  it('patch module') do
    Datadog::Monkey.patch_module(:rails)
    assert_warning_issued('Monkey#patch_module')
  end
  it('patch') do
    Datadog::Monkey.patch([:rails, :rack])
    assert_warning_issued('Monkey#patch')
  end
  it('get patched modules') do
    expect(Datadog::Monkey.get_patched_modules).to(eq({}))
    assert_warning_issued('Monkey#get_patched_modules')
  end
  it('without warnings') do
    Datadog::Monkey.without_warnings { nil }
    assert_warning_issued('Monkey#without_warnings')
  end
end
