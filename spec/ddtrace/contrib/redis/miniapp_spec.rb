require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'

require 'time'
require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis mini app test' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  before do
    Datadog.configure { |c| c.use :redis }

    # Configure client instance with custom options
    Datadog.configure(client, service_name: 'test-service')
  end

  let(:client) do
    if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
      redis._client
    else
      redis.client
    end
  end

  let(:redis) { Redis.new(host: host, port: port) }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  context 'when a trace is performed' do
    before do
      # now this is how you make sure that the redis spans are sub-spans
      # of the apps parent spans:
      tracer.trace('publish') do |span|
        span.service = 'webapp'
        span.resource = '/index'
        tracer.trace('process') do |subspan|
          subspan.service = 'datalayer'
          subspan.resource = 'home'
          redis.get 'data1'
          redis.pipelined do
            redis.set 'data2', 'something'
            redis.get 'data2'
          end
        end
      end
    end

    # span[1] (publish_span)
    #   \
    #    ------> span[0] (process_span)
    #              \
    #               |-----> span[2] (redis_cmd1_span)
    #               \-----> span[3] (redis_cmd2_span)
    let(:publish_span) { spans[1] }
    let(:process_span) { spans[0] }
    let(:redis_cmd1_span) { spans[2] }
    let(:redis_cmd2_span) { spans[3] }

    it { expect(spans).to have(4).items }

    describe '"publish span"' do
      it do
        expect(publish_span.name).to eq('publish')
        expect(publish_span.service).to eq('webapp')
        expect(publish_span.resource).to eq('/index')
        expect(publish_span.span_id).to_not eq(publish_span.trace_id)
        expect(publish_span.parent_id).to eq(0)
      end
    end

    describe '"process span"' do
      it do
        expect(process_span.name).to eq('process')
        expect(process_span.service).to eq('datalayer')
        expect(process_span.resource).to eq('home')
        expect(process_span.parent_id).to eq(publish_span.span_id)
        expect(process_span.trace_id).to eq(publish_span.trace_id)
      end
    end

    describe '"command spans"' do
      it do
        expect(redis_cmd1_span.name).to eq('redis.command')
        expect(redis_cmd1_span.service).to eq('test-service')
        expect(redis_cmd1_span.parent_id).to eq(process_span.span_id)
        expect(redis_cmd1_span.trace_id).to eq(publish_span.trace_id)

        expect(redis_cmd2_span.name).to eq('redis.command')
        expect(redis_cmd2_span.service).to eq('test-service')
        expect(redis_cmd2_span.parent_id).to eq(process_span.span_id)
        expect(redis_cmd2_span.trace_id).to eq(publish_span.trace_id)
      end

      it_behaves_like 'a peer service span' do
        let(:span) { redis_cmd1_span }
      end

      it_behaves_like 'a peer service span' do
        let(:span) { redis_cmd2_span }
      end
    end
  end
end
