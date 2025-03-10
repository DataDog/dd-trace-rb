require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Instrumentation do
  describe '::set_http_route_tags' do
    let(:tracing_enabled) { true }

    before do
      expect(Datadog::Tracing).to receive(:enabled?).and_return(tracing_enabled)
    end

    context 'when tracing is disabled' do
      let(:tracing_enabled) { false }

      it 'sets no tags' do
        Datadog::Tracing.trace('rack.request') do |_span, trace|
          described_class.set_http_route_tags('/users/:id', '/auth')

          expect(trace.send(:meta)).not_to have_key('http.route')
          expect(trace.send(:meta)).not_to have_key('http.route.path')
        end
      end
    end

    it 'sets http.route and http.route.path tags on existing trace' do
      Datadog::Tracing.trace('rack.request') do |_span, trace|
        described_class.set_http_route_tags('/users/:id(.:format)', '/auth')

        expect(trace.send(:meta).fetch('http.route')).to eq('/users/:id')
        expect(trace.send(:meta).fetch('http.route.path')).to eq('/auth')
      end
    end

    it 'sets no http.route.path when script name is nil' do
      Datadog::Tracing.trace('rack.request') do |_span, trace|
        described_class.set_http_route_tags('/users/:id(.:format)', nil)

        expect(trace.send(:meta).fetch('http.route')).to eq('/users/:id')
        expect(trace.send(:meta)).not_to have_key('http.route.path')
      end
    end

    it 'sets no tags when route spec is nil' do
      Datadog::Tracing.trace('rack.request') do |_span, trace|
        described_class.set_http_route_tags(nil, '/auth')

        expect(trace.send(:meta)).not_to have_key('http.route')
        expect(trace.send(:meta)).not_to have_key('http.route.path')
      end
    end

    it 'does not create new traces when no active trace is present' do
      described_class.set_http_route_tags('/users/:id', '/auth')

      expect(traces).to be_empty
    end
  end
end
