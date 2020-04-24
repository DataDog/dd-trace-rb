require 'spec_helper'

require 'ddtrace/profiling/transport/response'

RSpec.describe Datadog::Profiling::Transport::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Profiling::Transport::Response })
    end
  end
end
