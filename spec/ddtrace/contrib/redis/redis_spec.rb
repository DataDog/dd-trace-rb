require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'time'
require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis test' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :redis, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
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

    shared_context 'password-protected Redis server' do
      let(:redis) { Redis.new(host: host, port: port, driver: driver, password: password) }
      let(:password) { 'foobar' }

      before do
        allow(client).to receive(:process).and_call_original

        expect(client).to receive(:process)
          .with([[:auth, password]])
          .and_return("+OK\r\n")
      end
    end

    shared_examples_for 'a span with common tags' do
      it do
        expect(span).to_not be nil
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port)
        expect(span.get_tag('out.redis_db')).to eq(0)
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
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

    context 'arguments wrapped in array' do
      before(:each) do
        expect(redis.call([:set, 'FOO', 'bar'])).to eq('OK')
      end

      it { expect(all_spans).to have(1).item }

      describe 'span' do
        subject(:span) { all_spans[-1] }

        it do
          expect(span.resource).to eq('SET FOO bar')
          expect(span.get_tag('redis.raw_command')).to eq('SET FOO bar')
        end
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
      describe 'set span' do
        subject(:span) { all_spans.first }

        before { expect(redis.set('K', 'x' * 500)).to eq('OK') }

        it do
          expect(all_spans).to have(1).items
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('SET K ' + 'x' * 47 + '...')
          expect(span.get_tag('redis.raw_command')).to eq('SET K ' + 'x' * 47 + '...')
        end

        it_behaves_like 'a span with common tags'
      end

      describe 'get span' do
        subject(:span) { all_spans.first }

        before do
          expect(redis.set('K', 'x' * 500)).to eq('OK')
          expect(redis.get('K')).to eq('x' * 500)
        end

        it do
          expect(all_spans).to have(2).items
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('GET K')
          expect(span.get_tag('redis.raw_command')).to eq('GET K')
        end

        it_behaves_like 'a span with common tags'
      end

      describe 'auth span' do
        include_context 'password-protected Redis server'

        subject(:span) { all_spans.first }

        before { redis.auth(password) }

        it do
          expect(all_spans).to have(1).items
          expect(span.name).to eq('redis.command')
          expect(span.service).to eq('redis')
          expect(span.resource).to eq('AUTH ?')
          expect(span.get_tag('redis.raw_command')).to eq('AUTH ?')
        end
      end
    end
  end

  it_behaves_like 'a Redis driver', :ruby
  it_behaves_like 'a Redis driver', :hiredis
end
