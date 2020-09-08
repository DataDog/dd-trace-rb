require 'ddtrace/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe Datadog::Contrib::Sidekiq::Patcher do
  before do
    # Sidekiq 3.x unfortunately doesn't let us access server_middleware unless
    # actually a server, so we just have to skip them.
    skip if Gem.loaded_specs['sidekiq'].version < Gem::Version.new('4.0')

    Sidekiq.client_middleware.clear
    Sidekiq.server_middleware.clear

    allow(Sidekiq).to receive(:server?).and_return(server)
    # NB: This is needed because we want to patch multiple times.
    allow(described_class).to receive(:do_once).with(:patch).and_yield
  end

  # NB: This needs to be after the before block above so that the use :sidekiq
  # executes after the allows are setup.
  include_context 'Sidekiq testing'

  context 'for a client' do
    let(:server) { false }

    it 'correctly patches' do
      expect(Sidekiq.client_middleware.entries.map(&:klass)).to eq([Datadog::Contrib::Sidekiq::ClientTracer])
      expect(Sidekiq.server_middleware.entries.map(&:klass)).to eq([])
    end
  end

  context 'for a server' do
    let(:server) { true }

    it 'correctly patches' do
      expect(Sidekiq.client_middleware.entries.map(&:klass)).to eq([Datadog::Contrib::Sidekiq::ClientTracer])
      expect(Sidekiq.server_middleware.entries.map(&:klass)).to eq([Datadog::Contrib::Sidekiq::ServerTracer])
    end
  end
end
