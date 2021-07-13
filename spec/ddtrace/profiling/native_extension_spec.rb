require 'ddtrace/profiling/native_extension'

RSpec.describe Datadog::Profiling::NativeExtension do
  before do
    skip('Profiling not supported on JRuby') if PlatformHelpers.jruby?

    begin
      require "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
    rescue LoadError
      raise 'Profiling native extension does not seem to be compiled. ' \
        'Try running `bundle exec rake compile` before running this test.'
    end
  end

  describe '.working?' do
    subject(:working?) { described_class.send(:working?) }

    it { is_expected.to be true }
  end
end
