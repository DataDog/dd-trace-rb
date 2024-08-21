require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Instrumentation do
  describe '::format_http_route' do
    it 'removes (.:format) part of the route' do
      expect(described_class.format_http_route('/api/users/:id(.:format)')).to eq('/api/users/:id')
    end

    it 'does not remove optional params from the route' do
      expect(described_class.format_http_route('/api/users/(:id)')).to eq('/api/users/(:id)')
    end
  end
end
