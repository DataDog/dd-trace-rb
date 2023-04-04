require 'datadog/core/utils'
require 'datadog/tracing'
require 'datadog/tracing/contrib/sidekiq/client_tracer'
require 'datadog/tracing/contrib/sidekiq/server_tracer'
require 'sidekiq/testing'

RSpec.shared_context 'Sidekiq testing' do
  include SidekiqTestingConfiguration

  before { configure_sidekiq }

  let!(:empty_worker) do
    stub_const(
      'EmptyWorker',
      Class.new do
        include Sidekiq::Worker
        def perform; end
      end
    )
  end
end

module SidekiqTestingConfiguration
  def configure_sidekiq
    Datadog.configure do |c|
      c.tracing.instrument :sidekiq
    end

    redis_host = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1')
    redis_port = ENV.fetch('TEST_REDIS_PORT', 6379)

    redis_url = "redis://#{redis_host}:#{redis_port}"

    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq::Testing.inline!
  end
end

module SidekiqServerExpectations
  include SidekiqTestingConfiguration

  def expect_in_sidekiq_server(wait_until: nil)
    app_tempfile = Tempfile.new(['sidekiq-server-app', '.rb'])

    expect_in_fork do
      # NB: This is needed because we want to patch within a forked process.
      if Datadog::Tracing::Contrib::Sidekiq::Patcher.instance_variable_get(:@patch_only_once)
        Datadog::Tracing::Contrib::Sidekiq::Patcher
          .instance_variable_get(:@patch_only_once)
          .send(:reset_ran_once_state_for_tests)
      end

      require 'sidekiq/cli'

      configure_sidekiq

      t = Thread.new do
        cli = Sidekiq::CLI.instance
        cli.parse(['--require', app_tempfile.path]) # boot the "app"
        cli.run
      end

      try_wait_until(seconds: 10) { wait_until.call } if wait_until

      Thread.kill(t)

      yield
    end
  ensure
    app_tempfile.close
    app_tempfile.unlink
  end

  def expect_after_stopping_sidekiq_server
    expect_in_fork do
      # NB: This is needed because we want to patch within a forked process.
      if Datadog::Tracing::Contrib::Sidekiq::Patcher.instance_variable_get(:@patch_only_once)
        Datadog::Tracing::Contrib::Sidekiq::Patcher
          .instance_variable_get(:@patch_only_once)
          .send(:reset_ran_once_state_for_tests)
      end

      require 'sidekiq/cli'

      configure_sidekiq

      # Change options and constants for Sidekiq to stop faster:
      # Reduce number of threads and shutdown timeout.

      # Since the `options` changes across different Sidekiq version.
      options = if Sidekiq::VERSION.start_with? '6.5'
                  Sidekiq.tap do |s|
                    s[:concurrency] = 1
                    s[:timeout] = 0
                  end
                else
                  Sidekiq.options.merge(concurrency: 1, timeout: 0)
                end

      # `Sidekiq::Launcher#stop` sleeps before actually starting to shutting down Sidekiq.
      # Settings `Manager::PAUSE_TIME` to zero removes that wait.
      stub_const('Sidekiq::Manager::PAUSE_TIME', 0)

      # `Sidekiq::Launcher#stop` ultimately class `Sidekiq::Manager#hard_shutdown` as a final
      # shutdown step. `#hard_shutdown` has a hard-coded minimum timeout of 3 seconds when checking
      # if workers have finished, using the `Util#wait_for` method.
      #
      # `Util::PAUSE_TIME` controls how frequently `Util#wait_for` checks that workers have finished.
      # Setting `Util::PAUSE_TIME` to less than the timeout (3 seconds) actually makes the
      # shutdown process slower: `Util#wait_for` behaves like a busy-wait loop if `Util::PAUSE_TIME` is less than
      # the timeout. Sidekiq defaults are actually such case: The default value for `PAUSE_TIME` is
      # `$stdout.tty? ? 0.1 : 0.5` which is less than 3. This ensures a busy-wait loop, which makes shutdown
      # slower as worker threads don't the opportunity to process their shutdown instructions.
      #
      # Setting this value to 3 seconds or higher makes the shutdown process almost immediate, as
      # `Util#wait_for` checks immediately if workers have shut down, which is normally the case at this point.
      stub_const('Sidekiq::Util::PAUSE_TIME', 3)

      launcher = Sidekiq::Launcher.new(options)
      launcher.stop

      yield
    end
  end
end
