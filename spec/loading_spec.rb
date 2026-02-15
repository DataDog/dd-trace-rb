require 'shellwords'
require 'open3'

REQUIRES = [
  {require: 'datadog', check: 'Datadog::Core'},
  {require: 'datadog/appsec', check: 'Datadog::AppSec'},
  {require: 'datadog/ai_guard', check: 'Datadog::AIGuard'},
  {require: 'datadog/core', check: 'Datadog::Core'},
  {require: 'datadog/data_streams', check: 'Datadog::DataStreams'},
  {require: 'datadog/error_tracking', check: 'Datadog::ErrorTracking'},
  {require: 'datadog/di', check: 'Datadog::DI',
   env: {DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'false'},
   condition: -> { RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby' }},
  # DI initializes itsef when it's loaded and the environment variable
  # instructs DI to be enabled, therefore needs separate tests with the
  # environment variable being enabled and disabled.
  {require: 'datadog/di', check: 'Datadog::DI',
   env: {DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'true'},
   condition: -> { RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby' }},
  {require: 'datadog/di/preload', check: 'Datadog::DI::CodeTracker',
   condition: -> { RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby' }},
  {require: 'datadog/kit', check: 'Datadog::Kit'},
  {require: 'datadog/profiling', check: 'Datadog::Profiling'},
  {require: 'datadog/tracing', check: 'Datadog::Tracing'},
  {require: 'datadog/open_feature', check: 'Datadog::OpenFeature'},
].freeze

RSpec.describe 'loading of products' do
  REQUIRES.each do |spec|
    req = spec.fetch(:require)

    context req do
      if (env = spec[:env])
        with_env(**env)
      end

      let(:const) { spec.fetch(:check) }
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

      if (condition = spec[:condition])
        before do
          skip 'condition is false' unless condition.call
        end
      end

      it 'loads successfully by itself' do
        rv = system("ruby -e #{Shellwords.shellescape(code)}")
        expect(rv).to be true
      end

      it 'produces no output' do
        run_ruby_code_and_verify_no_output(code)
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

  it 'produces no output' do
    run_ruby_code_and_verify_no_output(code)
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
