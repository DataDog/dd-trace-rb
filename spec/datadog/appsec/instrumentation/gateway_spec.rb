# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/instrumentation/gateway'

RSpec.describe Datadog::AppSec::Instrumentation::Gateway do
  subject(:gateway) { described_class.new }
  let(:middlewares) { gateway.instance_variable_get(:@middlewares) }

  describe '#watch' do
    it 'stores middleware' do
      expect(middlewares['hello']).to be_empty

      gateway.watch('hello') do
        1 + 1
      end

      expect(middlewares['hello']).to_not be_empty
    end

    it 'stores multiple middlewares for the same event name' do
      gateway.watch('hello') do
        1 + 1
      end

      gateway.watch('hello') do
        2 + 2
      end

      expect(middlewares['hello'].length).to eq(2)
    end
  end

  describe '#push' do
    it 'returns provided block if no middleware present' do
      block_result, opts = gateway.push('hello', {}) do
        1 + 1
      end

      expect(block_result).to eq(2)
      expect(opts).to be nil
    end

    it 'wraps the stored middlewares on top of the provided block' do
      env_1 = nil
      env_2 = nil

      gateway.watch('hello') do |next_, env|
        env_dup = env.dup
        env_1 = env_dup
        env[:c] = :d
        next_.call(env)
      end

      gateway.watch('hello') do |next_, env|
        env_2 = env
        next_.call(env)
      end

      result = gateway.push('hello', {a: :b}) do
        [1 + 1, :done]
      end

      expect(result[0][0]).to eq(2)
      expect(result[0][1]).to eq(:done)
      expect(env_1).to eq({a: :b})
      expect(env_2).to eq({a: :b, c: :d})
    end
  end
end
