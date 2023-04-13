require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'semantic_logger'
require 'datadog/tracing/contrib/semantic_logger/patcher'

RSpec.describe Datadog::Tracing::Contrib::SemanticLogger::Patcher do
  describe '.patch' do
    it 'adds Instrumentation to ancestors of SemanticLogger::Logger class' do
      described_class.patch

      expect(SemanticLogger::Logger.ancestors).to include(Datadog::Tracing::Contrib::SemanticLogger::Instrumentation)
    end
  end
end
