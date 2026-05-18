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

  # The wrapper accepts both kwargs-syntax options and a trailing positional
  # options Hash — Ruby's two distinct ways to pass Process.spawn options.
  # Without `**opts` in the wrapper signature, kwargs at the call site
  # collapse into the trailing positional arg in *args; `super` then
  # forwards them to Process.spawn which accepts either form.
  describe 'option-syntax compatibility' do
    before do
      skip 'Fork not supported' unless Process.respond_to?(:fork)
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
    end

    def run_spawn_capture(*spawn_args)
      read_io, write_io = IO.pipe
      pipe_opts = { out: write_io, err: write_io, in: File::NULL }
      if spawn_args.last.is_a?(Hash) && spawn_args.last.keys.all? { |k| k.is_a?(Symbol) || k.is_a?(Integer) }
        spawn_args[-1] = spawn_args.last.merge(pipe_opts)
      else
        spawn_args << pipe_opts
      end
      pid = Process.spawn(*spawn_args)
      write_io.close
      out = read_io.read
      read_io.close
      _, status = Process.wait2(pid)
      [status.exitstatus, out]
    end

    it 'kwargs-syntax options work (Process.spawn(cmd, kw: value))' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {} })
        status, out = run_spawn_capture(%(printf 'hello\n'), pgroup: true)
        expect(status).to eq(0)
        expect(out).to include('hello')
      end
    end

    it 'positional Hash options work (opts = {...}; Process.spawn(cmd, opts))' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {} })
        options = { pgroup: true }
        status, out = run_spawn_capture(%(printf 'hello\n'), options)
        expect(status).to eq(0)
        expect(out).to include('hello')
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
