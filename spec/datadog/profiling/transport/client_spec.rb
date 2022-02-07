# typed: false
require 'spec_helper'

require 'datadog/profiling/flush'
require 'datadog/profiling/transport/client'

RSpec.describe Datadog::Profiling::Transport::Client do
  context 'when implemented in a Class' do
    subject(:client) { client_class.new }

    let(:client_class) { Class.new { include Datadog::Profiling::Transport::Client } }

    describe '#send_profiling_flush' do
      subject(:send_profiling_flush) { client.send_profiling_flush(flush) }

      let(:flush) { instance_double(Datadog::Profiling::OldFlush) }

      it { expect { send_profiling_flush }.to raise_error(NotImplementedError) }
    end
  end
end
