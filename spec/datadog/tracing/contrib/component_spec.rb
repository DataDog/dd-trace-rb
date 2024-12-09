require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/component'

RSpec.describe Datadog::Tracing::Contrib::Component do
  context 'integration test' do
    let(:config) { Datadog.configuration }

    after { described_class.send(:unregister, 'my-test') }
    it 'calls registered block' do
      block = proc {}

      allow(block).to receive(:call).with(config)

      described_class.register('my-test', &block)

      described_class.configure(config)

      expect(block).to have_received(:call).with(config)
    end
  end
end
