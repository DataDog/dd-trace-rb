require 'spec_helper'
require 'ddtrace/contrib/delayed_job/plugin'

require_relative 'app'

RSpec.describe Datadog::Contrib::DelayedJob::Plugin do
  describe '#patch' do
    let(:worker_plugins) { [] }
    let!(:delayed_worker_class) { class_double('Delayed::Worker', plugins: worker_plugins).as_stubbed_const }

    before do
      described_class.send(:unpatch)
    end

    context 'when delayed job is not present' do
      before do
        hide_const('Delayed')
      end

      it "shouldn't patch the code" do
        expect { described_class.patch }.not_to change { described_class.patched? }
      end
    end

    it 'should patch the code' do
      expect { described_class.patch }.to change { described_class.patched? }.from(false).to(true)
    end

    it 'add plugin to worker class' do
      expect { described_class.patch }.to change { worker_plugins.first }.to be_truthy
    end

    it 'pins the worker class' do
      expect { described_class.patch }.to change { Datadog::Pin.get_from(delayed_worker_class) }
                                              .to be_an_instance_of(Datadog::Pin)
    end
  end
end
