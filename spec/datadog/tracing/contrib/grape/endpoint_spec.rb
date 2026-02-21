require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/grape/endpoint'

RSpec.describe Datadog::Tracing::Contrib::Grape::Endpoint do
  describe '.api_view' do
    subject(:api_view) { described_class.send(:api_view, api) }

    context 'when api inherits from Grape::API::Instance and responds to base (Grape >= 1.2.0, < 2.3.0)' do
      let(:api) do
        stub_const('Grape::API::Instance', Class.new)
        stub_const(
          'TestAPI',
          Class.new(Grape::API::Instance) do
            def self.base
              'TestAPIBase'
            end
          end
        )
      end

      it 'returns the base class name' do
        expect(api_view).to eq('TestAPIBase')
      end
    end

    # This test covers Grape < 1.2.0 where the API is an Grape::API::Instance and not a class,
    # as well as Grape >= 2.3.0 where the base attr_reader was removed
    # See: https://github.com/ruby-grape/grape/commit/98214705fb61e3e90583bd3ad2b9889daa1bc794
    context 'when api inherits from Grape::API::Instance but does not respond to base (Grape < 1.2.0 or Grape >= 2.3.0)' do
      let(:api) do
        stub_const('Grape::API::Instance', Class.new)
        stub_const('TestAPIWithoutBase', Class.new(Grape::API::Instance))
      end

      it 'returns the api class name via to_s' do
        expect(api_view).to eq('TestAPIWithoutBase')
      end
    end
  end
end
