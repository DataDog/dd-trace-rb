require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require_relative 'delayed_job_active_record'

RSpec.describe Datadog::Tracing::Contrib::DelayedJob::Patcher, :delayed_job_active_record do
  describe '.patch' do
    let(:worker_plugins) { [] }
    let!(:delayed_worker_class) { class_double('Delayed::Worker', plugins: worker_plugins).as_stubbed_const }

    # Prevents random order from breaking tests
    before { remove_patch!(:delayed_job) }

    after { remove_patch!(:delayed_job) }

    it 'patches the code' do
      expect { described_class.patch }.to change { described_class.patched? }.from(false).to(true)
    end

    it 'add plugin to worker class' do
      expect { described_class.patch }.to change { worker_plugins.first }.to be_truthy
    end
  end
end
