require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/analytics_examples'

require 'datadog/tracing/contrib/redis/ext'

RSpec.shared_examples_for 'a redis span with common tags' do
  it do
    expect(span.name).to eq('redis.command')
    expect(span.get_tag('out.host')).to eq(host)
    expect(span.get_tag('out.port')).to eq(port)
    expect(span.get_tag('out.redis_db')).to eq(0)
    expect(span.get_tag('db.system')).to eq('redis')
    expect(span.get_tag('span.kind')).to eq('client')
  end
end

RSpec.shared_examples_for 'redis instrumentation' do |options = {}|
  context 'roundtrip' do
    # Run a roundtrip
    before do
      expect(redis.set('FOO', 'bar')).to eq('OK')
      expect(redis.get('FOO')).to eq('bar')
    end

    it { expect(spans).to have(2).items }

    describe 'set span' do
      let(:span) { spans[-1] }

      it do
        expect(span.service).to eq(options[:service_name] || 'redis')
        if options[:command_args]
          expect(span.resource).to eq('SET FOO bar')
          expect(span.get_tag('redis.raw_command')).to eq('SET FOO bar')
        else
          expect(span.resource).to eq('SET')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end

    describe 'get span' do
      let(:span) { spans[0] }

      it do
        expect(span.service).to eq(options[:service_name] || 'redis')

        if options[:command_args]
          expect(span.resource).to eq('GET FOO')
          expect(span.get_tag('redis.raw_command')).to eq('GET FOO')
        else
          expect(span.resource).to eq('GET')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end

  context 'arguments wrapped in array' do
    before do
      expect(redis.call([:set, 'FOO', 'bar'])).to eq('OK')
    end

    it { expect(spans).to have(1).item }

    describe 'span' do
      let(:span) { spans[-1] }

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it do
        if options[:command_args]
          expect(span.resource).to eq('SET FOO bar')
          expect(span.get_tag('redis.raw_command')).to eq('SET FOO bar')
        else
          expect(span.resource).to eq('SET')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end
    end
  end

  context 'pipeline' do
    before { pipeline }

    let(:pipeline) do
      if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('5.0.0')
        redis.pipelined do |p|
          p.set('v1', '0')
          p.set('v2', '0')
          p.incr('v1')
          p.incr('v2')
          p.incr('v2')
        end
      else
        redis.pipelined do
          redis.set('v1', '0')
          redis.set('v2', '0')
          redis.incr('v1')
          redis.incr('v2')
          redis.incr('v2')
        end
      end
    end

    it do
      expect(pipeline).to eq(['OK', 'OK', 1, 1, 2])
      expect(spans).to have(1).items
    end

    describe 'span' do
      let(:span) { spans[-1] }

      it do
        expect(span.get_metric('redis.pipeline_length')).to eq(5)
        expect(span.service).to eq(options[:service_name] || 'redis')
        if options[:command_args]
          expect(span.resource).to eq("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2")
          expect(span.get_tag('redis.raw_command')).to eq("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2")
        else
          expect(span.resource).to eq("SET\nSET\nINCR\nINCR\nINCR")
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end

  context 'empty pipeline' do
    before do
      skip if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('5.0.0')
      empty_pipeline
    end

    subject(:empty_pipeline) do
      redis.pipelined do |_|
        # DO NOTHING
      end
    end

    it do
      expect(empty_pipeline).to eq([])
      expect(spans).to have(1).items
    end

    describe 'span' do
      let(:span) { spans[-1] }

      it do
        expect(span.get_metric('redis.pipeline_length')).to eq(0)
        expect(span.service).to eq(options[:service_name] || 'redis')
        expect(span.resource).to eq('(none)')

        if options[:command_args]
          expect(span.get_tag('redis.raw_command')).to eq('(none)')
        else
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end

  context 'error' do
    subject(:bad_call) do
      redis.call 'THIS_IS_NOT_A_REDIS_FUNC', 'THIS_IS_NOT_A_VALID_ARG'
    end

    before do
      expect { bad_call }.to raise_error(Redis::CommandError, /ERR unknown command/)
    end

    it do
      expect(spans).to have(1).items
    end

    describe 'span' do
      subject(:span) { spans[-1] }

      it do
        expect(span.service).to eq(options[:service_name] || 'redis')

        if options[:command_args]
          expect(span.resource).to eq('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG')
          expect(span.get_tag('redis.raw_command')).to eq('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG')
        else
          expect(span.resource).to eq('THIS_IS_NOT_A_REDIS_FUNC')
          expect(span.get_tag('redis.raw_command')).to be_nil

        end
        expect(span.status).to eq(1)
        expect(span.get_tag('error.message')).to match(/ERR unknown command/)
        expect(span.get_tag('error.type')).to match(/CommandError/)
        expect(span.get_tag('error.stack').length).to be >= 3
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end

  context 'quantize' do
    describe 'set span' do
      before { expect(redis.set('K', 'x' * 500)).to eq('OK') }

      it do
        expect(span.service).to eq(options[:service_name] || 'redis')

        if options[:command_args]
          expect(span.resource).to eq("SET K #{'x' * 47}...")
          expect(span.get_tag('redis.raw_command')).to eq("SET K #{'x' * 47}...")
        else
          expect(span.resource).to eq('SET')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end

    describe 'get span' do
      let(:span) { spans.first }

      before do
        expect(redis.set('K', 'x' * 500)).to eq('OK')
        expect(redis.get('K')).to eq('x' * 500)
      end

      it do
        expect(spans).to have(2).items
        expect(span.service).to eq(options[:service_name] || 'redis')
        if options[:command_args]
          expect(span.resource).to eq('GET K')
          expect(span.get_tag('redis.raw_command')).to eq('GET K')
        else
          expect(span.resource).to eq('GET')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end

      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Redis::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end
end

RSpec.shared_examples_for 'an authenticated redis instrumentation' do |options = {}|
  describe 'when given username and password' do
    let(:span) { spans.first }
    let(:username) { 'data' }
    let(:password) { 'dog' }

    around do |example|
      ::Redis.new(default_redis_options).tap do |r|
        r.call('ACL', 'SETUSER', username, 'on', ">#{password}", '+@all')
        example.run
        r.call('ACL', 'DELUSER', username)
      end
    end

    shared_examples 'an authentication span' do
      it do
        expect(span.service).to eq(options[:service_name] || 'redis')

        if options[:command_args]
          expect(span.resource).to eq('AUTH ?')
          expect(span.get_tag('redis.raw_command')).to eq('AUTH ?')
        else
          expect(span.resource).to eq('AUTH')
          expect(span.get_tag('redis.raw_command')).to be_nil
        end
      end
    end

    context 'with auth command' do
      before do
        if Gem::Version.new(::Redis::VERSION) < Gem::Version.new('4.0.0')
          # Since 3.x does not support `username`
          # This is a workaround to test `auth` command without setting a password-protected redis instance
          # https://github.com/redis/redis-rb/blob/3.3/lib/redis.rb#L127-L131
          redis.client.call([:auth, username, password])
        else
          redis.auth(username, password)
        end
      end

      it_behaves_like 'an authentication span'
      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end

    context 'with `url`' do
      let(:redis) do
        Redis.new(
          redis_options.merge(
            url: "redis://#{username}:#{password}@#{redis_options[:host]}:#{redis_options[:port]}"
          )
        )
      end

      before do
        skip if Gem::Version.new(::Redis::VERSION) < Gem::Version.new('4.0.0')
        redis.ping
      end

      it { expect(spans).to have(2).items }

      it_behaves_like 'an authentication span'
      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end

    context 'with redis optins' do
      let(:redis) do
        Redis.new(
          redis_options.merge(
            username: username,
            password: password
          ).freeze
        )
      end

      before do
        skip if Gem::Version.new(::Redis::VERSION) < Gem::Version.new('4.0.0')
        redis.ping
      end

      it { expect(spans).to have(2).items }

      it_behaves_like 'an authentication span'
      it_behaves_like 'a redis span with common tags'
      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end
  end
end
