require 'spec_helper'

require 'time'
require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis test' do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :redis, tracer: tracer
    end
  end

  shared_examples_for 'a Redis driver' do |driver|
    let(:redis) { Redis.new(host: host, port: port, driver: driver) }
    let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
    let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

    let(:client) do
      if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
        redis._client
      else
        redis.client
      end
    end

    let(:pin) { Datadog::Pin.get_from(client) }

    it { expect(pin).to_not be nil }
    it { expect(pin.app_type).to eq('db') }

    shared_examples_for 'a span with common tags' do
      it do
        expect(span).to_not be nil
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('out.redis_db')).to eq('0')
      end
    end

    context 'roundtrip' do
      # Run a roundtrip
      before(:each) do
        expect(redis.set('FOO', 'bar')).to eq('OK')
        expect(redis.get('FOO')).to eq('bar')
      end

      it { expect(all_spans).to have(2).items }

      describe 'set span' do
        subject(:span) { all_spans[-1] }

        it do
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('SET FOO bar')
          expect(span.get_tag('redis.raw_command')).to eq('SET FOO bar')
        end

        it_behaves_like 'a span with common tags'
      end

      describe 'get span' do
        subject(:span) { all_spans[0] }

        it do
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('GET FOO')
          expect(span.get_tag('redis.raw_command')).to eq('GET FOO')
        end

        it_behaves_like 'a span with common tags'
      end
    end

    context 'pipeline' do
      before(:each) do
        redis.pipelined do
          responses << redis.set('v1', '0')
          responses << redis.set('v2', '0')
          responses << redis.incr('v1')
          responses << redis.incr('v2')
          responses << redis.incr('v2')
        end
      end

      let(:responses) { [] }

      it do
        expect(responses.map(&:value)).to eq(['OK', 'OK', 1, 1, 2])
        expect(all_spans).to have(1).items
      end

      describe 'span' do
        subject(:span) { all_spans[-1] }

        it do
          expect(span.get_metric('redis.pipeline_length')).to eq(5)
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2")
          expect(span.get_tag('redis.raw_command')).to eq("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2")
        end

        it_behaves_like 'a span with common tags'
      end
    end

    context 'error' do
      subject(:bad_call) do
        redis.call 'THIS_IS_NOT_A_REDIS_FUNC', 'THIS_IS_NOT_A_VALID_ARG'
      end

      before(:each) do
        expect { bad_call }.to raise_error(Redis::CommandError, "ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'")
      end

      it do
        expect(all_spans).to have(1).items
      end

      describe 'span' do
        subject(:span) { all_spans[-1] }

        it do
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG')
          expect(span.get_tag('redis.raw_command')).to eq('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG')
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg')).to eq("ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'")
          expect(span.get_tag('error.type')).to eq('Redis::CommandError')
          expect(span.get_tag('error.stack').length).to be >= 3
        end

        it_behaves_like 'a span with common tags'
      end
    end

    context 'quantize' do
      before(:each) do
        expect(redis.set('K', 'x' * 500)).to eq('OK')
        expect(redis.get('K')).to eq('x' * 500)
      end

      it { expect(all_spans).to have(2).items }

      describe 'set span' do
        subject(:span) { all_spans[-1] }

        it do
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('SET K ' + 'x' * 47 + '...')
          expect(span.get_tag('redis.raw_command')).to eq('SET K ' + 'x' * 47 + '...')
        end

        it_behaves_like 'a span with common tags'
      end

      describe 'get span' do
        subject(:span) { all_spans[-2] }

        it do
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('GET K')
          expect(span.get_tag('redis.raw_command')).to eq('GET K')
        end

        it_behaves_like 'a span with common tags'
      end
    end

    context 'service name' do
      let(:services) { tracer.writer.services }
      let(:service_name) { 'redis-test' }

      before(:each) do
        redis.set 'FOO', 'bar'
        tracer.writer.services # empty queue
        Datadog.configure(
          client,
          service_name: service_name,
          tracer: tracer,
          app_type: Datadog::Ext::AppTypes::CACHE
        )
        redis.set 'FOO', 'bar'
      end

      it do
        expect(services).to have(1).items
        expect(services[service_name]).to eq('app' => 'redis', 'app_type' => 'cache')
      end
    end
  end

  it_behaves_like 'a Redis driver', :ruby
  it_behaves_like 'a Redis driver', :hiredis
end
