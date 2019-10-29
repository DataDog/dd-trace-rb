require 'spec_helper'

require 'ddtrace/span'

RSpec.describe Datadog::Span::ExternalResource do
  let(:span) { Datadog::Span.new(nil, 'dummy', options) }
  let(:options) { {} }

  describe '#external_resource?' do
    subject(:external_resource?) { span.external_resource? }

    shared_examples 'internal resource' do |span_type|
      context "with '#{span_type}' span type" do
        let(:span_type) { span_type }

        it { is_expected.to be false }
      end
    end

    shared_examples 'external resource' do |span_type|
      context "with '#{span_type}' span type" do
        let(:span_type) { span_type }

        it { is_expected.to be true }
      end
    end

    context 'with span type set' do
      let(:options) { { span_type: span_type } }

      it_behaves_like 'internal resource', 'custom'
      it_behaves_like 'internal resource', 'template'
      it_behaves_like 'internal resource', 'web'
      it_behaves_like 'internal resource', 'worker'

      it_behaves_like 'external resource', 'cache'
      it_behaves_like 'external resource', 'db'
      it_behaves_like 'external resource', 'elasticsearch'
      it_behaves_like 'external resource', 'http'
      it_behaves_like 'external resource', 'memcached'
      it_behaves_like 'external resource', 'mongodb'
      it_behaves_like 'external resource', 'proxy'
      it_behaves_like 'external resource', 'redis'
      it_behaves_like 'external resource', 'sql'

      it_behaves_like 'external resource', 'new and unknown type'
    end

    context 'with span type not set' do
      it { is_expected.to be false }
    end
  end
end
