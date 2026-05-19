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

  # Regression coverage for https://github.com/DataDog/dd-trace-rb/issues/5621.
  #
  # The wrapper's env-detection check uses bare `Hash`, which resolves to
  # `Datadog::Core::Utils::Hash` (a refinement module) via Module.nesting
  # once that file is loaded — silently returning `false` for real Hashes.
  # The function then takes the "no env provided" branch and prepends
  # `DATADOG_ENV.to_h`, pushing the caller's env-Hash into the command slot
  # and producing `TypeError: no implicit conversion of Hash into String`.
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
      if spawn_args.last.is_a?(Hash) && spawn_args.last.keys.all? { |k| k.is_a?(Symbol) || k.is_a?(Integer) }
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
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn(probe_cmd)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(cmd, kw: ...) — kwargs option syntax' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn(probe_cmd, pgroup: true)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(cmd, options_hash) — positional options hash variable' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        options = {pgroup: true}
        ok, status, out = run_spawn(probe_cmd, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'spawn(env_hash, cmd)' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        ok, status, out = run_spawn({'EXTRA' => '1'}, probe_cmd)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # Terrapin: `Process.spawn(env, command, options.merge(pipe.pipe_options))`
    it 'spawn(env_hash, cmd, options_hash) — terrapin shape' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
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
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
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
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        options = {pgroup: true}
        ok, status, out = run_spawn({}, ['/bin/sh', 'argv0-name'], '-c', probe_cmd, options)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    # ChildProcess sets `options[writer.fileno] = :close` on duplex pipes, producing
    # an options Hash with mixed Integer + Symbol keys. On Ruby 2.5/2.6/2.7 the prior
    # wrapper signature `def spawn(*args, **opts)` auto-extracted the Symbol-keyed
    # entries into `**opts` while leaving Integer-keyed entries in the trailing
    # positional Hash — mangling the call and raising `TypeError`. The per-version
    # split in the wrapper (Ruby 2.x drops `**opts`) keeps the options Hash positional
    # and intact. No env-Hash is passed here so the test is independent of the
    # constant-shadow fix in PR #5773.
    it 'spawn(cmd, options_hash_with_mixed_symbol_and_integer_keys) — childprocess close-on-exec shape' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
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

    it 'spawn(env, cmd, **opts) — caller uses kwargs splat' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
        opts = {pgroup: true}
        ok, status, out = run_spawn({'EXTRA' => '1'}, probe_cmd, **opts)
        expect(ok).to be(true)
        expect(status).to eq(0)
        expect(out).to include("LINEAGE=#{lineage_val}")
      end
    end

    it 'parent process ENV reaches the child when caller passes an env hash' do
      expect_in_fork do
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
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
        described_class.apply!(lineage_envs_provider: -> { {lineage_var => lineage_val} })
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
