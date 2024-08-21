require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Instrumentation do
  describe '::set_http_route_tag' do
    it 'sets http_route tag without (.:format) part' do
      Datadog::Tracing.trace('web.request') do |span_op, _trace_op|
        described_class.set_http_route_tag('/api/users/:id(.:format)')

        expect(span_op.tags.fetch('http.route')).to eq('/api/users/:id')
      end
    end

    it 'does not set http_route tag when the route is empty' do
      Datadog::Tracing.trace('web.request') do |span_op, _trace_op|
        described_class.set_http_route_tag('')

        expect(span_op.tags).not_to have_key('http.route')
      end
    end
  end
end
