require 'datadog/tracing/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe Datadog::Tracing::Contrib::Sidekiq::Patcher do
  before do
    # Sidekiq 3.x unfortunately doesn't let us access server_middleware unless
    # actually a server, so we just have to skip them.
    skip if Gem.loaded_specs['sidekiq'].version < Gem::Version.new('4.0')

    Sidekiq.client_middleware.clear
    Sidekiq.server_middleware.clear

    allow(Sidekiq).to receive(:server?).and_return(server)

    # these are only loaded when `Sidekiq::CLI` is actually loaded,
    # which we don't want to do here because it mutates global state
    stub_const('Sidekiq::Launcher', Class.new)
    stub_const('Sidekiq::Processor', Class.new)
    stub_const('Sidekiq::Scheduled::Poller', Class.new)
    stub_const('Sidekiq::ServerInternalTracer::RedisInfo', Class.new)

    # NB: This is needed because we want to patch multiple times.
    if described_class.instance_variable_get(:@patch_only_once)
      described_class.instance_variable_get(:@patch_only_once).send(:reset_ran_once_state_for_tests)
    end
  end

  # NB: This needs to be after the before block above so that the use :sidekiq
  # executes after the allows are setup.
  include_context 'Sidekiq testing'

  context 'for a client' do
    let(:server) { false }

    it 'correctly patches' do
      expect(Sidekiq.client_middleware.entries.map(&:klass)).to eq([Datadog::Tracing::Contrib::Sidekiq::ClientTracer])
      expect(Sidekiq.server_middleware.entries.map(&:klass)).to eq([])
    end
  end

  context 'for a server' do
    let(:server) { true }

    it 'correctly patches' do
      expect(Sidekiq.client_middleware.entries.map(&:klass)).to eq([Datadog::Tracing::Contrib::Sidekiq::ClientTracer])
      expect(Sidekiq.server_middleware.entries.map(&:klass)).to eq([Datadog::Tracing::Contrib::Sidekiq::ServerTracer])
    end
  end
end
