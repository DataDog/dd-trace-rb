# frozen_string_literal: true

### BRAZE TEST — validates Patch #1 (Redis instrumentation enhancements)
### See: docs/plans/2026-02-13-v2.27.0-rebase-qa-plan.md
### Patched files: lib/datadog/tracing/contrib/redis/trace_middleware.rb
###
### These tests verify that TraceMiddleware.call sets Braze-specific
### metrics: redis.key, redis.raw_command_length, redis.raw_response_length.

require 'spec_helper'
require 'datadog/tracing/contrib/redis/trace_middleware'
require 'datadog/tracing/contrib/redis/ext'

RSpec.describe 'Braze Redis TraceMiddleware metrics' do
  let(:redis_config) { double('redis_config', host: '127.0.0.1', port: 6379, db: 0) }
  let(:service_name) { 'test-redis' }
  let(:command_args) { true }

  # Collect spans via the test tracer
  before do
    Datadog.configure do |c|
      c.tracing.instrument :redis
    end
  end

  describe '.call' do
    let(:command) { ['GET', 'user:123:profile'] }
    let(:result) { 'some_cached_value' }

    it 'sets redis.key from the command second element' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call(redis_config, command, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_KEY)).to eq('user:123:profile')
    end

    it 'sets redis.raw_command_length as the byte length of the raw command string' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call(redis_config, command, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      raw_command_str = span.resource
      expect(span.get_metric(Datadog::Tracing::Contrib::Redis::Ext::METRIC_RAW_COMMAND_LEN)).to be > 0
    end

    it 'sets redis.raw_response_length from the result bytesize' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call(redis_config, command, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      expect(span.get_metric(Datadog::Tracing::Contrib::Redis::Ext::METRIC_RESP_COMMAND_LEN)).to eq(result.to_s.bytesize)
    end

    context 'with a single-element command (no key)' do
      let(:command) { ['PING'] }

      it 'does not set redis.key' do
        span = nil
        Datadog::Tracing::Contrib::Redis::TraceMiddleware.call(redis_config, command, service_name, command_args) do
          span = Datadog::Tracing.active_span
          'PONG'
        end

        expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_KEY)).to be_nil
      end
    end

    context 'with a nil result' do
      it 'sets redis.raw_response_length to 0' do
        span = nil
        Datadog::Tracing::Contrib::Redis::TraceMiddleware.call(redis_config, command, service_name, command_args) do
          span = Datadog::Tracing.active_span
          nil
        end

        expect(span.get_metric(Datadog::Tracing::Contrib::Redis::Ext::METRIC_RESP_COMMAND_LEN)).to eq(0)
      end
    end
  end

  describe '.call_pipelined' do
    let(:commands) { [['SET', 'key1', 'val1'], ['GET', 'key2']] }
    let(:result) { ['OK', 'val2'] }

    it 'sets redis.raw_command_length for the pipeline' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call_pipelined(redis_config, commands, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      expect(span.get_metric(Datadog::Tracing::Contrib::Redis::Ext::METRIC_RAW_COMMAND_LEN)).to be > 0
    end

    it 'sets redis.raw_response_length for the pipeline result' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call_pipelined(redis_config, commands, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      expect(span.get_metric(Datadog::Tracing::Contrib::Redis::Ext::METRIC_RESP_COMMAND_LEN)).to eq(result.to_s.bytesize)
    end

    it 'does not set redis.key for pipelines' do
      span = nil
      Datadog::Tracing::Contrib::Redis::TraceMiddleware.call_pipelined(redis_config, commands, service_name, command_args) do
        span = Datadog::Tracing.active_span
        result
      end

      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_KEY)).to be_nil
    end
  end
end
