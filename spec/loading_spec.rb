require 'shellwords'
require 'open3'

REQUIRES = [
  ['datadog', 'Datadog::Core'],
  ['datadog/appsec', 'Datadog::AppSec'],
  ['datadog/core', 'Datadog::Core'],
  ['datadog/di', 'Datadog::DI',
   -> { RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby' }],
  ['datadog/di/preload', 'Datadog::DI::CodeTracker',
   -> { RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby' }],
  ['datadog/kit', 'Datadog::Kit'],
  ['datadog/profiling', 'Datadog::Profiling'],
  ['datadog/tracing', 'Datadog::Tracing'],
].freeze

RSpec.describe 'loading of products' do
  REQUIRES.each do |(req, const, condition)|
    context req do
      if condition
        before do
          skip 'condition is false' unless condition.call
        end
      end

      let(:code) do
        <<-E
          if defined?(Datadog)
            unless Datadog.constants == [:VERSION]
              exit 1
            end
          end

          require "#{req}"

          unless defined?(#{const})
            exit 1
          end

          exit 0
        E
      end

      it 'loads successfully by itself' do
        rv = system("ruby -e #{Shellwords.shellescape(code)}")
        expect(rv).to be true
      end

      it 'produces no output' do
        out, status = Open3.capture2e('ruby', '-w', stdin_data: code)
        raise("Test script failed with exit status #{status.exitstatus}:\n#{out}") unless status.success?
        raise("Test script produced unexpected output: #{out}") unless out.empty?
      end
    end
  end
end

RSpec.describe 'load core only and configure library with no settings' do
  let(:code) do
    <<-E
      if defined?(Datadog)
        unless Datadog.constants == [:VERSION]
          exit 1
        end
      end

      require 'datadog/core'

      Datadog.configure do
      end
    E
  end

  it 'configures successfully' do
    rv = system("ruby -e #{Shellwords.shellescape(code)}")
    expect(rv).to be true
  end
end

RSpec.describe 'load datadog and enable dynamic instrumentation' do
  let(:code) do
    <<-E
      if defined?(Datadog)
        unless Datadog.constants == [:VERSION]
          exit 1
        end
      end

      require 'datadog'

      Datadog.configure do |c|
        c.dynamic_instrumentation.enabled = true
      end
    E
  end

  # DI is not available in all environments, however asking for it to be
  # turned on should not produce exceptions.
  it 'configures successfully' do
    rv = system("ruby -e #{Shellwords.shellescape(code)}")
    expect(rv).to be true
  end
end
