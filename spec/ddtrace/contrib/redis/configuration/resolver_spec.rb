require 'ddtrace/contrib/support/spec_helper'

require 'redis'
require 'ddtrace'

RSpec.describe 'Redis configuration resolver' do
  let(:resolver) { Datadog::Contrib::Redis::Configuration::Resolver.new }

  context 'when :default magic keyword' do
    it { expect(resolver.resolve(:default)).to eq(:default) }
  end

  context 'when unix socket provided' do
    let(:options) { { url: 'unix://path/to/file' } }

    it do
      expect(resolver.resolve(options)).to eq(url: 'unix://path/to/file')
    end
  end

  context 'when redis connexion string provided' do
    let(:options) { { url: 'redis://127.0.0.1:6379/0' } }

    it do
      expect(resolver.resolve(options)).to eq(host: '127.0.0.1',
                                              port: 6379,
                                              db: 0,
                                              scheme: 'redis')
    end
  end

  context 'when host, port, db and scheme provided' do
    let(:options) do
      {
        host: '127.0.0.1',
        port: 6379,
        db: 0,
        scheme: 'redis'
      }
    end

    it do
      expect(resolver.resolve(options)).to eq(host: '127.0.0.1',
                                              port: 6379,
                                              db: 0,
                                              scheme: 'redis')
    end
  end

  context 'when host, port and db provided' do
    let(:options) do
      {
        host: '127.0.0.1',
        port: 6379,
        db: 0
      }
    end

    it do
      expect(resolver.resolve(options)).to eq(host: '127.0.0.1',
                                              port: 6379,
                                              db: 0,
                                              scheme: 'redis')
    end
  end

  context 'when host and portprovided' do
    let(:options) do
      {
        host: '127.0.0.1',
        port: 6379
      }
    end

    it do
      expect(resolver.resolve(options)).to eq(host: '127.0.0.1',
                                              port: 6379,
                                              db: 0,
                                              scheme: 'redis')
    end
  end
end
