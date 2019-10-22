require 'spec_helper'

require 'ddtrace/context'
require_relative 'shared_examples'

RSpec.describe Datadog::Context::Flush::Finished do
  subject(:context_flush) { described_class.new }

  describe '#consume' do
    subject(:consume) { context_flush.consume(context) }

    include_context 'trace context'
    it_behaves_like 'a context flusher'
  end
end
