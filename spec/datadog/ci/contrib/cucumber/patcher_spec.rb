require 'datadog/ci/contrib/support/spec_helper'
require 'datadog/ci/contrib/cucumber/patcher'

require 'cucumber'

RSpec.describe Datadog::CI::Contrib::Cucumber::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:runtime) { Cucumber::Runtime.new }

    before do
      described_class.patch
    end

    context 'is patched' do
      let(:handlers) { runtime.configuration.event_bus.instance_variable_get(:@handlers) }

      it 'has a custom formatter in formatters' do
        expect(runtime.formatters).to include(runtime.datadog_formatter)
        expect(handlers).to include(&runtime.datadog_formatter.method(:on_test_case_started))
        expect(handlers).to include(&runtime.datadog_formatter.method(:on_test_case_finished))
        expect(handlers).to include(&runtime.datadog_formatter.method(:on_test_step_started))
        expect(handlers).to include(&runtime.datadog_formatter.method(:on_test_step_finished))
      end
    end
  end
end
