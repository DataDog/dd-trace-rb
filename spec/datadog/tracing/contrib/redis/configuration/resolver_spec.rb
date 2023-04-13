require 'datadog/tracing/contrib/support/spec_helper'

require 'redis'
require 'ddtrace'

RSpec.describe 'Redis configuration resolver' do
  let(:resolver) { Datadog::Tracing::Contrib::Redis::Configuration::Resolver.new }

  let(:config) { instance_double('config') }
  let(:matcher) {}

  describe '#add' do
    subject(:add) { resolver.add(matcher, config) }

    before { add }

    let(:parsed_key) do
      expect(resolver.configurations.keys).to have(1).item
      resolver.configurations.keys[0]
    end

    context 'when unix socket provided' do
      let(:matcher) { { url: 'unix://path/to/file' } }

      it { expect(parsed_key).to eq(url: 'unix://path/to/file') }
    end

    context 'when redis connexion string provided' do
      context 'as a plain object' do
        let(:matcher) { 'redis://127.0.0.1:6379/0' }

        it do
          expect(parsed_key).to eq(
            host: '127.0.0.1',
            port: 6379,
            db: 0,
            scheme: 'redis'
          )
        end
      end

      context 'as a hash' do
        let(:matcher) { { url: 'redis://127.0.0.1:6379/0' } }

        it do
          expect(parsed_key).to eq(
            host: '127.0.0.1',
            port: 6379,
            db: 0,
            scheme: 'redis'
          )
        end
      end
    end

    context 'when host, port, db and scheme provided' do
      let(:matcher) do
        {
          host: '127.0.0.1',
          port: 6379,
          db: 0,
          scheme: 'redis'
        }
      end

      it do
        expect(parsed_key).to eq(
          host: '127.0.0.1',
          port: 6379,
          db: 0,
          scheme: 'redis'
        )
      end
    end

    context 'when host, port, and db are provided' do
      let(:matcher) do
        {
          host: '127.0.0.1',
          port: 6379,
          db: 0
        }
      end

      it do
        expect(parsed_key).to eq(
          host: '127.0.0.1',
          port: 6379,
          db: 0,
          scheme: 'redis'
        )
      end
    end

    context 'when host and port are provided' do
      let(:matcher) do
        {
          host: '127.0.0.1',
          port: 6379
        }
      end

      it do
        expect(parsed_key).to eq(
          host: '127.0.0.1',
          port: 6379,
          db: 0,
          scheme: 'redis'
        )
      end
    end
  end

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(value) }

    let(:value) { matcher }

    context 'with a matcher' do
      before { resolver.add(matcher, config) }

      context 'when unix socket provided' do
        let(:matcher) { { url: 'unix://path/to/file' } }

        it_behaves_like 'a resolver with a matching pattern'
      end

      context 'when redis connexion string provided' do
        context 'as a plain object' do
          let(:matcher) { 'redis://127.0.0.1:6379/0' }

          it_behaves_like 'a resolver with a matching pattern'
        end

        context 'as a hash' do
          let(:matcher) { { url: 'redis://127.0.0.1:6379/0' } }

          it_behaves_like 'a resolver with a matching pattern'
        end
      end

      context 'when host, port, db and scheme provided' do
        let(:matcher) do
          {
            host: '127.0.0.1',
            port: 6379,
            db: 0,
            scheme: 'redis'
          }
        end

        it_behaves_like 'a resolver with a matching pattern'
      end

      context 'when host, port, and db are provided' do
        let(:matcher) do
          {
            host: '127.0.0.1',
            port: 6379,
            db: 0
          }
        end

        it_behaves_like 'a resolver with a matching pattern'
      end

      context 'when host and port are provided' do
        let(:matcher) do
          {
            host: '127.0.0.1',
            port: 6379
          }
        end

        it_behaves_like 'a resolver with a matching pattern'
      end
    end

    context 'with two matching matchers' do
      before do
        resolver.add(first_matcher, :first)
        resolver.add(second_matcher, :second)
      end

      let(:first_matcher) { 'redis://127.0.0.1:6379/0' }
      let(:second_matcher) { 'redis://127.0.0.1:6379' }

      let(:value) do
        {
          host: '127.0.0.1',
          port: 6379,
          db: 0,
          scheme: 'redis'
        }
      end

      it 'returns the latest added one' do
        is_expected.to eq(:second)
      end
    end
  end
end
