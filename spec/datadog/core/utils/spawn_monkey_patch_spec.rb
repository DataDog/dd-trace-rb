# frozen_string_literal: true

require 'datadog/core/utils/spawn_monkey_patch'
require 'datadog/core/configuration/components'
require 'datadog/core/configuration/settings'
require 'rbconfig'

RSpec.describe Datadog::Core::Utils::SpawnMonkeyPatch do
  let(:lineage_envs) do
    {
      Datadog::Core::Environment::Identity::ENV_ROOT_SESSION_ID => 'root-runtime-id',
      Datadog::Core::Environment::Identity::ENV_PARENT_SESSION_ID => 'parent-runtime-id',
    }
  end
  let(:lineage_script) do
    'print ENV.values_at("SPAWN_PATCH_PARENT_TEST", "_DD_ROOT_RB_SESSION_ID", ' \
      '"_DD_PARENT_RB_SESSION_ID").join(":")'
  end

  def spawn_output(*spawn_args)
    IO.pipe do |read_io, write_io|
      process_options = {in: File::NULL, out: write_io, err: write_io}
      process_options.merge!(spawn_args.pop) if ::Hash === spawn_args.last

      pid = Process.spawn(*spawn_args, process_options)
      write_io.close
      Process.wait(pid)

      read_io.read
    end
  end

  describe '::apply!' do
    subject(:apply!) { described_class.apply!(lineage_envs_provider: -> { lineage_envs }) }

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

  describe '::inject_lineage_envs' do
    subject(:inject_lineage_envs) { described_class.inject_lineage_envs(args) }

    before do
      described_class.apply!(lineage_envs_provider: -> { lineage_envs })
    end

    context 'when Process.spawn already has an env hash' do
      let(:args) { [existing_env, '/bin/sh', '-lc', 'exit 0', {pgroup: true}] }
      let(:existing_env) { {'BROWSER_PATH' => '/tmp/chrome'} }

      it 'merges the lineage envs into the existing env hash' do
        expect(inject_lineage_envs).to eq(
          [
            existing_env.merge(lineage_envs),
            '/bin/sh',
            '-lc',
            'exit 0',
            {pgroup: true},
          ],
        )
      end

      it 'does not mutate the existing env hash' do
        expect { inject_lineage_envs }.not_to change { existing_env }
      end
    end

    context 'when Process.spawn does not have an env hash' do
      let(:args) { ['/bin/sh', '-lc', 'exit 0', {pgroup: true}] }

      it 'prepends only the lineage envs' do
        expect(inject_lineage_envs).to eq(
          [
            lineage_envs,
            '/bin/sh',
            '-lc',
            'exit 0',
            {pgroup: true},
          ],
        )
      end
    end
  end

  describe 'patched Process.spawn' do
    subject(:apply!) { described_class.apply!(lineage_envs_provider: -> { lineage_envs }) }

    before do
      skip 'Fork not supported' unless Process.respond_to?(:fork)
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
    end

    it 'preserves Ferrum-style positional process options when an env hash is provided' do
      expect_in_fork do
        ENV['SPAWN_PATCH_PARENT_TEST'] = 'parent'
        apply!

        expect(spawn_output({}, RbConfig.ruby, '-e', lineage_script, pgroup: true))
          .to eq('parent:root-runtime-id:parent-runtime-id')
      end
    end

    it 'preserves keyword-style spawn options when no env hash is provided' do
      expect_in_fork do
        ENV['SPAWN_PATCH_PARENT_TEST'] = 'parent'
        apply!

        expect(spawn_output(RbConfig.ruby, '-e', lineage_script, pgroup: true))
          .to eq('parent:root-runtime-id:parent-runtime-id')
      end
    end

    it 'respects unsetenv_others when an env hash is provided' do
      expect_in_fork do
        ENV['SPAWN_PATCH_PARENT_TEST'] = 'parent'
        script = 'print [ENV.fetch("SPAWN_PATCH_PARENT_TEST", "missing"), ' \
          '*ENV.values_at("EXPLICIT_CHILD_ENV", "_DD_ROOT_RB_SESSION_ID", ' \
          '"_DD_PARENT_RB_SESSION_ID")].join(":")'

        apply!

        expect(
          spawn_output(
            {'EXPLICIT_CHILD_ENV' => 'explicit'},
            RbConfig.ruby,
            '-e',
            script,
            unsetenv_others: true,
          ),
        ).to eq('missing:explicit:root-runtime-id:parent-runtime-id')
      end
    end

    it 'preserves explicit nil env values that unset variables in the child' do
      expect_in_fork do
        ENV['SPAWN_PATCH_DELETE_ME'] = 'parent'
        script = 'print [(ENV.key?("SPAWN_PATCH_DELETE_ME") ? "present" : "missing"), ' \
          '*ENV.values_at("_DD_ROOT_RB_SESSION_ID", "_DD_PARENT_RB_SESSION_ID")].join(":")'

        apply!

        expect(
          spawn_output({'SPAWN_PATCH_DELETE_ME' => nil}, RbConfig.ruby, '-e', script)
        ).to eq('missing:root-runtime-id:parent-runtime-id')
      end
    end

    it 'preserves array-form command variants when an env hash is provided' do
      expect_in_fork do
        ENV['SPAWN_PATCH_PARENT_TEST'] = 'parent'
        command = 'printf %s "$0:$SPAWN_PATCH_PARENT_TEST:$EXPLICIT_CHILD_ENV:' \
          '$_DD_ROOT_RB_SESSION_ID:$_DD_PARENT_RB_SESSION_ID"'

        apply!

        expect(
          spawn_output(
            {'EXPLICIT_CHILD_ENV' => 'explicit'},
            ['/bin/sh', 'custom-sh'],
            '-c',
            command,
          ),
        ).to eq('custom-sh:parent:explicit:root-runtime-id:parent-runtime-id')
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
