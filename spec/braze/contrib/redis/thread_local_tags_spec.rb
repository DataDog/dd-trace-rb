# frozen_string_literal: true

### BRAZE TEST — validates Patch #1 (Redis instrumentation enhancements)
### See: docs/plans/2026-02-13-v2.27.0-rebase-qa-plan.md
### Patched files: lib/datadog/tracing/contrib/redis/{ext,tags}.rb
###
### These tests verify that Braze's thread-local variables (set by
### Appboy::RedisTracing.trace_with_custom_tags in the platform repo)
### propagate to Datadog span tags via Tags.set_common_tags.

require 'spec_helper'
require 'datadog/tracing/contrib/redis/tags'
require 'datadog/tracing/contrib/redis/ext'
require 'datadog/tracing/span_operation'

RSpec.describe 'Braze Redis thread-local tag propagation' do
  let(:client) { double('client', host: '127.0.0.1', port: 6379, db: 0) }
  let(:span) { Datadog::Tracing::SpanOperation.new('redis.command') }
  let(:raw_command) { 'GET mykey' }

  before do
    allow(Datadog.configuration.tracing[:redis]).to receive(:[]).and_call_original
    allow(Datadog.configuration.tracing[:redis]).to receive(:[]).with(:peer_service).and_return(nil)
    allow(Datadog.configuration.tracing[:redis]).to receive(:[]).with(:analytics_enabled).and_return(nil)
    allow(Datadog.configuration).to receive(:service).and_return('test')
  end

  after do
    [
      Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_FILEPATH,
      Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_CODEOWNER,
      Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_SHARD_INDEX,
      Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_COMPANY_NAME,
    ].each { |key| Thread.current[key] = nil }
  end

  describe 'when thread-locals are set' do
    it 'sets redis.filepath tag' do
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_FILEPATH] = '/app/models/user.rb'
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_FILEPATH)).to eq('/app/models/user.rb')
    end

    it 'sets redis.codeowner tag' do
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_CODEOWNER] = '@Appboy/in-memory-data'
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_CODEOWNER)).to eq('@Appboy/in-memory-data')
    end

    it 'sets redis.shard_index tag' do
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_SHARD_INDEX] = '3'
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_SHARD_INDEX)).to eq('3')
    end

    it 'sets company_name tag' do
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_COMPANY_NAME] = 'acme_corp'
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_COMPANY_NAME)).to eq('acme_corp')
    end
  end

  describe 'when thread-locals are nil' do
    it 'does not set any Braze tags' do
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_FILEPATH)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_CODEOWNER)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_SHARD_INDEX)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_COMPANY_NAME)).to be_nil
    end
  end

  describe 'when only some thread-locals are set' do
    it 'sets only the tags with non-nil thread-locals' do
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_FILEPATH] = '/app/jobs/worker.rb'
      Thread.current[Datadog::Tracing::Contrib::Redis::Ext::THREAD_GLOBAL_SHARD_INDEX] = '7'
      Datadog::Tracing::Contrib::Redis::Tags.set_common_tags(client, span, raw_command)

      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_FILEPATH)).to eq('/app/jobs/worker.rb')
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_SHARD_INDEX)).to eq('7')
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_CODEOWNER)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Contrib::Redis::Ext::METRIC_COMPANY_NAME)).to be_nil
    end
  end
end
