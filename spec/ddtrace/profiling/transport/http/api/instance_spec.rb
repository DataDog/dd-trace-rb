require 'spec_helper'

require 'ddtrace/transport/http/env'
require 'ddtrace/profiling/transport/http/api/instance'
require 'ddtrace/profiling/transport/http/api/spec'
require 'ddtrace/profiling/transport/http/response'

RSpec.describe Datadog::Profiling::Transport::HTTP::API::Instance do
  subject(:instance) { described_class.new(spec, adapter) }
  let(:adapter) { double('adapter') }

  describe '#send_profiling_flush' do
    subject(:send_profiling_flush) { instance.send_profiling_flush(env) }
    let(:env) { instance_double(Datadog::Transport::HTTP::Env) }

    context 'when specification does not support traces' do
      let(:spec) { double('spec') }
      it do
        expect { send_profiling_flush }
          .to raise_error(Datadog::Profiling::Transport::HTTP::API::Instance::ProfilesNotSupportedError)
      end
    end

    context 'when specification supports traces' do
      let(:spec) { Datadog::Profiling::Transport::HTTP::API::Spec.new }
      let(:response) { instance_double(Datadog::Profiling::Transport::HTTP::Response) }

      before { expect(spec).to receive(:send_profiling_flush).with(env).and_return(response) }

      it { is_expected.to be response }
    end
  end
end
