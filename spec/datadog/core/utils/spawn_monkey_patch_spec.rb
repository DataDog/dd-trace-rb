# frozen_string_literal: true

require 'datadog/core/utils/spawn_monkey_patch'
require 'datadog/core/configuration/components'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Utils::SpawnMonkeyPatch do
  let(:envs) do
    {
      'ENV1' => 'val1',
      'ENV2' => 'val2',
    }
  end

  def process_spawn(*spawn_args)
    IO.pipe do |read_io, write_io|
      process_options = {in: File::NULL, out: write_io, err: write_io}
      process_options.merge!(spawn_args.pop) if ::Hash === spawn_args.last

      pid = Process.spawn(*spawn_args, process_options)
      write_io.close
      Process.wait(pid)

      Hash[read_io.read.lines.map { |line| line.chomp.split('=', 2) }]
    end
  end

  describe '::apply!' do
    subject(:apply!) { described_class.apply!(env_provider: -> { envs }) }

    context 'when Process.spawn is supported' do
      before do
        skip 'Fork not supported' unless Process.respond_to?(:fork)
        skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
      end

      it 'prepends the spawn monkey patch' do
        apply!
        expect(Process.singleton_class.ancestors).to include(described_class::ProcessSpawnPatch)
        expect(Process.method(:spawn).source_location.first).to match(/spawn_monkey_patch\.rb/)
      end

      it 'does not patch twice' do
        described_class.apply!(env_provider: -> { {'ENV1' => 'val1'} })
        described_class.apply!(env_provider: -> { {'ENV1' => 'val2'} })

        expect(Process.singleton_class.ancestors.count(described_class::ProcessSpawnPatch)).to eq(1)
        expect(process_spawn('/usr/bin/env')).to include('ENV1' => 'val2')
      end
    end
  end

  describe 'on Process.spawn' do
    subject(:apply!) { described_class.apply!(env_provider: -> { envs }) }

    around do |example|
      ClimateControl.modify('PARENT1' => 'parent_val') { example.run }
    end

    before do
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
      apply!
    end

    it 'merges env_provider, parent envs, and env argument' do
      output = process_spawn({'ARG' => 'arg_val'}, '/usr/bin/env', pgroup: true)

      expect(output).to include('PARENT1' => 'parent_val', 'ENV1' => 'val1', 'ENV2' => 'val2', 'ARG' => 'arg_val')
    end

    it 'merges env_provider and parent envs when no env argument is provided' do
      output = process_spawn('/usr/bin/env', pgroup: true)

      expect(output).to include('PARENT1' => 'parent_val', 'ENV1' => 'val1', 'ENV2' => 'val2')
    end

    it 'respects parent env removal through the value `nil`' do
      output = process_spawn({'PARENT1' => nil}, '/usr/bin/env')

      expect(output).not_to include('PARENT1')
      expect(output).to include('ENV1' => 'val1', 'ENV2' => 'val2')
    end

    it 'respects array-form command variant' do
      command = 'printf %s "$0:$ARG:$PARENT1:$ENV1:$ENV2"'

      output = IO.pipe do |read_io, write_io|
        pid = Process.spawn(
          {'ARG' => 'arg_val'},
          ['/bin/sh', 'cmd-name'],
          '-c',
          command,
          in: File::NULL,
          out: write_io,
          err: write_io,
        )
        write_io.close
        Process.wait(pid)

        read_io.read
      end

      expect(output).to eq('cmd-name:arg_val:parent_val:val1:val2')
    end
  end

  describe '::inject_envs' do
    subject(:inject_envs) { described_class.inject_envs(args.dup) }
    let(:args) { [env_argument, '/bin/ls', '.', { pgroup: 0 }] }
    let(:env_argument) { {'TZ' => 'UTC'} }

    before do
      described_class.apply!(env_provider: -> { envs })
    end

    it 'does not mutate the provided env argument Hash' do
      expect { inject_envs }.not_to change { env_argument }
    end
  end

  describe 'Components initialization' do
    reset_at_fork_monkey_patch_for_components!

    before do
      skip 'Fork not supported' unless Process.respond_to?(:fork)
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
    end

    it 'applies both fork and spawn patches when Components is initialized' do
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
