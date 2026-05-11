# frozen_string_literal: true

require 'datadog/core/utils/spawn_monkey_patch'
require 'datadog/core/configuration/components'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Utils::SpawnMonkeyPatch do
  describe '::apply!' do
    subject(:apply!) { described_class.apply!(lineage_envs_provider: -> { {} }) }

    context 'when Process.spawn is supported' do
      before do
        skip 'Fork not supported' unless Process.respond_to?(:fork)
        skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
      end

      it 'prepends the spawn monkey patch' do
        expect_in_fork do
          apply!
          expect(Process.singleton_class.ancestors).to include(described_class::ProcessSpawnPatch)
          expect(Process.method(:spawn).source_location.first).to match(/spawn_monkey_patch\.rb/)
        end
      end
    end
  end

  describe 'Components initialization' do
    reset_at_fork_monkey_patch_for_components!

    before do
      skip 'Fork not supported' unless Process.respond_to?(:fork)
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
    end

    it 'applies both fork and spawn patches when Components is initialized' do
      expect_in_fork do
        Datadog::Core::Configuration::Components.new(Datadog::Core::Configuration::Settings.new)

        expect(Process.singleton_class.ancestors).to include(
          Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch,
        )
        expect(Process.singleton_class.ancestors).to include(
          Datadog::Core::Utils::SpawnMonkeyPatch::ProcessSpawnPatch,
        )
      end
    end
  end
end
