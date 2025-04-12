# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::Kernel do
  subject(:require_gem) { require(gem) }

  let(:gem) { 'pstore' } # Any default gem that is not already loaded: https://stdgems.org/
  let(:kernel) { described_class }

  before do
    if $LOADED_FEATURES.any? { |path| path.end_with?("/lib/#{gem}.rb") }
      raise "gem #{gem} already loaded. Please provide a different default gem."
    end
  end

  it 'does not affect require if not callback is registered' do
    expect_in_fork do
      kernel::Patcher.patch

      expect(require_gem).to eq(true)
    end
  end

  it 'invokes callback on first require' do
    expect_in_fork do
      kernel::Patcher.patch

      executed_times = 0
      kernel.on_require(gem) { executed_times += 1 }

      expect(require_gem).to eq(true)

      expect(executed_times).to eq(1)
    end
  end

  it 'does not invoke callback on successive requires' do
    expect_in_fork do
      kernel::Patcher.patch

      executed_times = 0
      kernel.on_require(gem) { executed_times += 1 }

      expect(require(gem)).to eq(true)
      expect(require(gem)).to eq(false)

      expect(executed_times).to eq(1)
    end
  end

  it 'overrides the callback on registering with the same name' do
    expect_in_fork do
      kernel::Patcher.patch

      executed_times = 0

      kernel.on_require(gem) { raise 'Should not be called' }
      kernel.on_require(gem) { executed_times += 1 }

      expect(require_gem).to eq(true)

      expect(executed_times).to eq(1)
    end
  end

  it 'does not affect require if callback raises error' do
    expect_in_fork do
      kernel::Patcher.patch

      kernel.on_require(gem) { raise }

      expect(require_gem).to eq(true)
    end
  end
end
