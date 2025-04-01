require 'shellwords'

REQUIRES = {
  'datadog/appsec' => 'Datadog::AppSec',
  'datadog/core' => 'Datadog::Core',
  'datadog/di' => 'Datadog::DI',
  'datadog/di/preload' => 'Datadog::DI::CodeTracker',
  'datadog/kit' => 'Datadog::Kit',
  'datadog/profiling' => 'Datadog::Profiling',
  'datadog/tracing' => 'Datadog::Tracing',
}.freeze

RSpec.describe 'loading of products' do
  REQUIRES.each do |req, const|
    context req do
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
    end
  end
end

RSpec.describe 'load core only and configure library' do
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
