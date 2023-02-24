require 'spec_helper'

require 'ddtrace/transport/http/api/instance'

RSpec.describe Datadog::Transport::HTTP::API::Instance do
  subject(:instance) { described_class.new(spec, adapter, options) }

  let(:spec) { double(Datadog::Transport::HTTP::API::Spec, encoder: encoder) }
  let(:encoder) { double }
  let(:adapter) { spy('adapter') }
  let(:options) { {} }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        spec: spec,
        adapter: adapter,
        headers: {}
      )
    end

    context 'given headers' do
      let(:options) { { headers: headers } }
      let(:headers) { { 'X-Test-Header' => 'true' } }

      it { expect(instance.headers).to eq(headers) }
    end
  end

  describe '#call' do
    let(:env) { instance_double(Datadog::Transport::HTTP::Env, headers: env_headers) }
    let(:env_headers) { {} }

    before { instance.call(env) }

    context 'when headers are' do
      context 'set' do
        let(:options) { { headers: { 'X-Test-Header' => 'true' } } }

        context 'and there are conflicting headers on the request env' do
          let(:env_headers) { { 'X-Test-Header' => 'false' } }

          it do
            expect(adapter).to have_received(:call) do |env|
              expect(env.headers).to eq(
                'X-Test-Header' => 'true'
              )
            end
          end
        end

        context 'and there are no conflicting headers set on the request env' do
          let(:env_headers) { { 'X-Other-Test-Header' => 'false' } }

          it do
            expect(adapter).to have_received(:call) do |env|
              expect(env.headers).to eq(
                'X-Test-Header' => 'true',
                'X-Other-Test-Header' => 'false'
              )
            end
          end
        end
      end

      context 'not set' do
        it { expect(adapter).to have_received(:call).with(env) }
      end
    end
  end

  describe '#encoder' do
    subject { instance.encoder }

    it { is_expected.to eq(encoder) }
  end
end
