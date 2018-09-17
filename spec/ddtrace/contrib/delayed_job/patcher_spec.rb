require 'spec_helper'
require 'ddtrace'
require_relative 'delayed_job_active_record'

RSpec.describe Datadog::Contrib::DelayedJob::Patcher, :delayed_job_active_record do
  describe '.patch' do
    let(:worker_plugins) { [] }
    let!(:delayed_worker_class) { class_double('Delayed::Worker', plugins: worker_plugins).as_stubbed_const }

    def remove_patch!
      Datadog.registry[:delayed_job].patcher.tap do |patcher|
        if patcher.instance_variable_defined?(:@done_once)
          patcher.instance_variable_get(:@done_once).delete(:delayed_job)
        end
      end
    end

    # Prevents random order from breaking tests
    before(:each) { remove_patch! }
    after(:each) { remove_patch! }

    it 'should patch the code' do
      expect { described_class.patch }.to change { described_class.patched? }.from(false).to(true)
    end

    it 'add plugin to worker class' do
      expect { described_class.patch }.to change { worker_plugins.first }.to be_truthy
    end
  end
end
