require('minitest')
require('minitest/autorun')
require('ddtrace')
require 'spec_helper'
RSpec.describe Datadog::Monkey do
  DEFAULT_LOG = Datadog::Tracer.log
  before do
    @buf = StringIO.new
    Datadog::Tracer.log = Datadog::Logger.new(@buf)
    Datadog::Tracer.log.level = ::Logger::WARN
  end
  after { Datadog::Tracer.log = DEFAULT_LOG }
  def assert_warning_issued(method)
    expect(Datadog::Tracer.log.warn?).to be_truthy
    lines = @buf.string.lines
    if lines.respond_to?(:length)
      expect(lines.length).to eq(6, 'there should be 1 log messages (with 6 lines)')
    end
    i = 0
    lines.each do |l|
      case i
      when 0 then
        expect(l).to match(/W,.*WARN -- ddtrace: \[ddtrace\] #{method}/)
      when 1 then
        expect(l).to match(/^\s+Datadog::Monkey has been REMOVED.*/)
      end
      i = (i + 1)
    end
  end
  it('registry') do
    expect(described_class.registry).to(eq(Datadog.registry))
    assert_warning_issued('Monkey#registry')
  end
  it('autopatch modules') do
    expect(described_class.autopatch_modules).to(eq({}))
    assert_warning_issued('Monkey#autopatch_modules')
  end
  it('patch module') do
    described_class.patch_module(:rails)
    assert_warning_issued('Monkey#patch_module')
  end
  it('patch') do
    described_class.patch([:rails, :rack])
    assert_warning_issued('Monkey#patch')
  end
  it('get patched modules') do
    expect(described_class.get_patched_modules).to(eq({}))
    assert_warning_issued('Monkey#get_patched_modules')
  end
  it('without warnings') do
    described_class.without_warnings { nil }
    assert_warning_issued('Monkey#without_warnings')
  end
end
