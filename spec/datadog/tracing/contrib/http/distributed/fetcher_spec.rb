require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/fetcher'
require 'datadog/tracing/span'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::Fetcher do
  subject(:fetcher) { described_class.new(env) }
  let(:env) { {} }

  describe '#[]' do
    subject(:get) { fetcher[key] }
    let(:key) {}

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a Rack header associated' do
      let(:key) { 'my-key' }

      context 'that is empty' do
        let(:env) { { 'HTTP_MY_KEY' => '' } }
        it { is_expected.to be_nil }
      end

      context 'that is not empty' do
        let(:env) { { 'HTTP_MY_KEY' => 'value' } }
        it { is_expected.to eq('value') }

        context 'and a plain header' do
          let(:env) { super().merge('my-key' => 'plain-match') }

          it 'prefers the plain header match' do
            is_expected.to eq('plain-match')
          end
        end
      end
    end

    context 'with a plain header associated' do
      let(:key) { 'rack.session' }

      context 'that is empty' do
        let(:env) { { key => '' } }
        it { is_expected.to be_nil }
      end

      context 'that is not empty' do
        let(:env) { { key => 'value' } }
        it { is_expected.to eq('value') }
      end
    end
  end
end
