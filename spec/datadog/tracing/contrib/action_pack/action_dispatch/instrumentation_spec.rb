require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Instrumentation do
  describe '::add_http_route_tag' do
    let(:active_span) { active_trace.active_span }
    let(:http_route) { '/api/users/:id(.:format)' }

    it 'sets http_route tag' do
      Datadog::Tracing.trace('web.request') do |_span_op, _trace_op|
        described_class.add_http_route_tag(http_route)
      end

      expect(spans).to have(1).item
      expect(spans.first.tags).to have_key('http.route')
    end

    it 'removes (.:format) route part' do
      Datadog::Tracing.trace('web.request') do |_span_op, _trace_op|
        described_class.add_http_route_tag(http_route)
      end

      expect(spans.first.tags.fetch('http.route')).to eq('/api/users/:id')
    end
  end
end
