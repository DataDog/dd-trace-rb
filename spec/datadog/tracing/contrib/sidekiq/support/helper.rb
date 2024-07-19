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

# Non-testing Sidekiq Server, performing the same operations as the production deployment.
RSpec.shared_context 'Sidekiq server' do
  include SidekiqServerExpectations

  before do
    unless Datadog::Tracing::Contrib::Sidekiq::Integration.compatible_with_server_internal_tracing?
      skip 'Sidekiq internal server tracing is not supported on this version.'
    end

    skip 'Sidekiq server requires forking' unless Process.respond_to?(:fork)

    # Fetches block for 2 seconds when there is nothing in the queue:
    # https://github.com/mperham/sidekiq/blob/v6.2.2/lib/sidekiq/fetch.rb#L7-L9
    # https://redis.io/commands/blpop#blocking-behavior
    #
    # We change the constant here to ensure test runs as fast possible.
    require 'sidekiq/fetch' # Require late, as this is not available if `compatible_with_server_internal_tracing?` is false
    stub_const('Sidekiq::BasicFetch::TIMEOUT', 0.0011) # A timeout lower than 0.0011 is rounded to zero

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
  def configure_sidekiq(log_level: Logger::ERROR)
    Datadog.configure do |c|
      c.tracing.instrument :sidekiq
    end

    redis_host = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1')
    redis_port = ENV.fetch('TEST_REDIS_PORT', 6379)

    redis_url = "redis://#{redis_host}:#{redis_port}"

    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
      config.logger.level = log_level
      config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: redis_url }
      config.logger.level = log_level
      config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    end

    Sidekiq::Testing.inline!
  end
end

module SidekiqServerExpectations
  include SidekiqTestingConfiguration

  def expect_in_sidekiq_server(
    wait_until: -> { fetch_spans.any? { |s| s.name == 'sidekiq.job_fetch' } },
    log_level: Logger::ERROR
  )
    app_tempfile = Tempfile.new(['sidekiq-server-app', '.rb'])

    expect_in_fork do
      # NB: This is needed because we want to patch within a forked process.
      if Datadog::Tracing::Contrib::Sidekiq::Patcher.instance_variable_get(:@patch_only_once)
        Datadog::Tracing::Contrib::Sidekiq::Patcher
          .instance_variable_get(:@patch_only_once)
          .send(:reset_ran_once_state_for_tests)
      end

      require 'sidekiq/cli'

      configure_sidekiq(log_level: log_level)

      Sidekiq::Testing.disable! # Ensure the real Sidekiq server is used to process the job

      t = Thread.new do
        cli = Sidekiq::CLI.instance
        cli.parse(['--require', app_tempfile.path, '--concurrency', '1']) # boot the "app"

        # Sidekiq waits between 5-15 seconds, and we cannot reduce it to less
        # than 5 seconds through configuration alone.
        # @see https://github.com/sidekiq/sidekiq/blob/fcc9406c02b809d18af419e164a8840630d60d23/lib/sidekiq/scheduled.rb#L219-L224
        #
        # Instead, we override the `#initial_wait` method to ensure it does not wait 5+ seconds.
        #
        # This is an `expect` instead of an `allow` because if Sidekiq's `#initial_wait`
        # logic moves somewhere else, the failure will be an obscure timeout error without
        # this assertion.
        expect_any_instance_of(Sidekiq::Scheduled::Poller).to receive(:initial_wait)

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

  def fetch_job_span
    try_wait_until { fetch_spans.find { |s| s.name == 'sidekiq.job' } }
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
      options = if Sidekiq.respond_to? :default_configuration
                  Sidekiq.default_configuration.tap do |c|
                    c[:concurrency] = 1
                    c[:timeout] = 0
                  end
                else
                  Sidekiq.options.tap do |c|
                    c[:concurrency] = 1
                    c[:timeout] = 0

                    unless c.respond_to? :logger
                      def c.logger
                        Sidekiq.logger
                      end
                    end
                  end
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
