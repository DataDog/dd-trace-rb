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

      Datadog::Core::Utils::EnumerableCompat.filter_map(read_io.read.lines) do |line|
        parts = line.chomp.split('=', 2)
        [parts[0], parts[1]] if parts.size == 2
      end.to_h
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

    it 'respects unsetenv_others and does not inherit parent ENV aside from injections' do
      output = process_spawn('/usr/bin/env', unsetenv_others: true)

      expect(output).to include('ENV1' => 'val1', 'ENV2' => 'val2')
      expect(output).not_to include('PARENT1')
      expect(output.keys).not_to include('')
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
    let(:args) { [env_argument, '/bin/ls', '.', {pgroup: 0}] }
    let(:env_argument) { {'TZ' => 'UTC'} }

    before do
      described_class.apply!(env_provider: -> { envs })
    end

    it 'does not mutate the provided env argument Hash' do
      expect { inject_envs }.not_to change { env_argument }
    end
  end

  # Regression coverage for https://github.com/DataDog/dd-trace-rb/issues/5621.
  #
  # When the env-detection check used bare `Hash`, it resolved to
  # `Datadog::Core::Utils::Hash` via Module.nesting,
  # so `Hash === real_env_hash` silently returned false. `#inject_envs` then took
  # the wrong branch and broke callers that pass an env `{Hash}` first
  # (TypeError: no implicit conversion of Hash into String).
  #
  # Implementation uses `::Hash === args.first` and forwards with `super(*args)`.
  #
  # Affected callers (named in the issue): childprocess, terrapin, launchy,
  # selenium-webdriver, cuprite/ferrum, danger.
  describe 'Process.spawn argument forms (issue #5621 regression)' do
    before do
      skip 'Fork not supported' unless Process.respond_to?(:fork)
      skip 'Process.spawn not supported' unless Process.respond_to?(:spawn)
    end

    # Inside-fork helper: append (or merge) pipe options into spawn_args,
    # run Process.spawn, return [success?, exit_status, child_stdout].
    def run_spawn(*spawn_args)
      read_io, write_io = IO.pipe
      if spawn_args.last.is_a?(Hash)
        spawn_args[-1] = spawn_args.last.merge(out: write_io, err: write_io, in: File::NULL)
      else
        spawn_args << {out: write_io, err: write_io, in: File::NULL}
      end
      pid = Process.spawn(*spawn_args)
      write_io.close
      output = read_io.read
      read_io.close
      _, status = Process.wait2(pid)
      [pid.is_a?(Integer), status.exitstatus, output]
    end

    let(:lineage_var) { 'DD_LINEAGE_PROBE' }
    let(:lineage_val) { 'lineage-value-zzz' }
    let(:probe_cmd) { %(printf 'LINEAGE=%s\n' "$#{lineage_var}") }

    it 'spawn(cmd_string) — no env, no options' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn(probe_cmd)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(cmd, kw: ...) — kwargs option syntax' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn(probe_cmd, pgroup: true)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(cmd, options_hash) — positional options hash variable' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        options = {pgroup: true}
        ok, status, out = run_spawn(probe_cmd, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(env_hash, cmd)' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn({'EXTRA' => '1'}, probe_cmd)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # Terrapin: `Process.spawn(env, command, options.merge(pipe.pipe_options))`
    it 'spawn(env_hash, cmd, options_hash) — terrapin shape' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        options = {pgroup: true}
        ok, status, out = run_spawn({'EXTRA' => '1'}, probe_cmd, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # ChildProcess multi-arg: `::Process.spawn(environment, *args, options)`
    it 'spawn(env_hash, *args, options_hash) — childprocess multi-arg shape' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        env = {}
        args = ['/bin/sh', '-c', probe_cmd]
        options = {pgroup: true}
        ok, status, out = run_spawn(env, *args, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # ChildProcess single-arg rewrites to `[cmd, argv0]`, producing
    # `Process.spawn(env, [cmd, argv0], options)`.
    it 'spawn(env_hash, [cmdname, argv0], options_hash) — childprocess single-arg shape' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        options = {pgroup: true}
        ok, status, out = run_spawn({}, ['/bin/sh', 'argv0-name'], '-c', probe_cmd, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # ChildProcess sets `options[writer.fileno] = :close` on duplex pipes, producing
    # an options Hash with mixed Integer + Symbol keys. The prior wrapper signature
    # `def spawn(*args, **opts)` auto-extracted the Symbol-keyed entries into `**opts`
    # on Ruby 2.5/2.6/2.7 while leaving Integer-keyed entries in the trailing positional
    # Hash — mangling the call and raising `TypeError`. Dropping `**opts`
    # keeps the options Hash positional and intact across all supported Rubies.
    it 'spawn(cmd, options_hash_with_mixed_symbol_and_integer_keys) — childprocess close-on-exec shape' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        spare_r, spare_w = IO.pipe
        begin
          options = {:pgroup => true, spare_r.fileno => :close, spare_w.fileno => :close}
          ok, status, out = run_spawn(probe_cmd, options)
          expect(ok).to be(true)
          expect(status).to eq(0)
          expect(out).to include("LINEAGE=#{lineage_val}")
        ensure
          spare_r.close
          spare_w.close
        end
      end
    end

    it 'delegates perfectly to the original method' do
      expect_in_fork do
        checker = double
        if RubyVersion.is?('< 2.7')
          # 2.6 splits Symbol & non-Symbol kwargs so we have to test just *args
          checker.define_singleton_method :spawn do |*args|
            checker.check(*args)
          end
        else
          checker.define_singleton_method :spawn do |*args, **kwargs|
            checker.check(*args, **kwargs)
          end
        end
        Datadog::Core::Utils::SpawnMonkeyPatch.instance_variable_set(:@env_provider, -> { {lineage_var => lineage_val} })
        checker.singleton_class.prepend(Datadog::Core::Utils::SpawnMonkeyPatch::ProcessSpawnPatch)

        expect(checker).to receive(:check).with({lineage_var => lineage_val}, ['echo', 'test'], 2 => 1, :out => File::NULL)
        checker.spawn(['echo', 'test'], 2 => 1, :out => File::NULL)
      end
    end

    it 'spawn(env, cmd, **opts) — caller uses kwargs splat' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        opts = {pgroup: true}
        ok, status, out = run_spawn({'EXTRA' => '1'}, probe_cmd, **opts)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'parent process ENV reaches the child when caller passes an env hash' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        ENV['PARENT_ONLY_VAR'] = 'parent-only-value'
        cmd = %(printf 'PARENT=%s\n' "$PARENT_ONLY_VAR")
        ok, status, out = run_spawn({'EXTRA' => '1'}, cmd)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include('PARENT=parent-only-value')
      end
    end

    it 'does not mutate the env Hash supplied by the caller' do
      expect_in_fork do
        described_class.apply!(env_provider: -> { {lineage_var => lineage_val} })
        caller_env = {'CALLER_KEY' => 'caller-value'}
        before_keys = caller_env.keys.dup
        run_spawn(caller_env, probe_cmd)
        expect(caller_env.keys).to eq(before_keys)
        expect(caller_env).not_to have_key(lineage_var)
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
