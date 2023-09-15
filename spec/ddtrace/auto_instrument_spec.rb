require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'

require 'sinatra/base'

# Loading 'ddtrace/auto_instrument' has side effects and can't
# easily be undone. This test should run on its own process.
RSpec.describe 'Auto Instrumentation of non Rails' do
  include Rack::Test::Methods

  before do
    RSpec.configure do |config|
      unless config.files_to_run.one?
        raise 'auto_instrument_spec.rb should be run on a separate RSpec process, do not run it together with other specs'
      end
    end
    require 'ddtrace/auto_instrument'
  end

  after { Datadog.registry[:sinatra].reset_configuration! }

  describe 'request which runs a query' do
    subject(:response) { post '/' }

    let(:app) do
      Class.new(Sinatra::Application) do
        post '/' do
          ''
        end
      end
    end

    it 'auto_instruments all relevant gems automatically' do
      is_expected.to be_ok
      expect(spans).to have_at_least(3).items

      rack_span = spans.find { |s| s.name == 'rack.request' }
      expect(rack_span).to_not have_error

      sinatra_request_span = spans.find { |s| s.name == 'sinatra.request' }
      expect(sinatra_request_span).to_not have_error

      sinatra_route_span = spans.find { |s| s.name == 'sinatra.route' }
      expect(sinatra_route_span).to_not have_error
    end
  end
end

RSpec.describe 'LOADED variable' do
  subject(:auto_instrument) { load 'ddtrace/auto_instrument.rb' }
  it do
    auto_instrument
    expect(Datadog::AutoInstrument::LOADED).to eq(true)
  end
end

RSpec.describe 'Profiler startup' do
  subject(:auto_instrument) { load 'ddtrace/auto_instrument.rb' }

  it 'starts the profiler' do
    expect(Datadog::Profiling).to receive(:start_if_enabled)
    auto_instrument
  end
end
