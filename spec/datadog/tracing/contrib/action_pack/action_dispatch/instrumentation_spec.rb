require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Instrumentation do
  describe '::set_http_route_tag' do
    it 'sets http_route tag without (.:format) part' do
      Datadog::Tracing.trace('web.request') do |_span_op, trace_op|
        described_class.set_http_route_tag('/api/users/:id(.:format)')

        expect(trace_op.tags.fetch('http.route')).to eq('/api/users/:id')
      end
    end

    it 'does not set http_route tag when the route is nil' do
      Datadog::Tracing.trace('web.request') do |_span_op, trace_op|
        described_class.set_http_route_tag(nil)

        expect(trace_op.tags).not_to have_key('http.route')
      end
    end
  end
end
