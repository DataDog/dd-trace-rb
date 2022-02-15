# typed: ignore
require 'datadog/core/utils'
require 'datadog/tracing'
require 'datadog/tracing/contrib/sidekiq/client_tracer'
require 'datadog/tracing/contrib/sidekiq/server_tracer'
require 'sidekiq/testing'

RSpec.shared_context 'Sidekiq testing' do
  include SidekiqTestingConfiguration

  before { configure_sidekiq }

  let!(:empty_worker) do
    stub_const('EmptyWorker', Class.new do
      include Sidekiq::Worker
      def perform; end
    end)
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

  def expect_in_sidekiq_server(duration: 2, &expectations)
    app_tempfile = Tempfile.new(['sidekiq-server-app', '.rb'])

    expect_in_fork(
      # Due to the expectations being run in an `at_exit` hook, to have visibility into the
      # spans created in the forked process, the exit status will be 0 even if our expectations fail.
      # Instead, look at `STDERR`, ignoring warnings.
      fork_expectations: proc do |status:, stdout:, stderr:|
        stdout = Datadog::Core::Utils.utf8_encode(stdout) if stdout
        stderr = Datadog::Core::Utils.utf8_encode(stderr) if stderr

        expect(status).to be_success, "STDOUT:`#{stdout}` STDERR:`#{stderr}"

        non_warning_testing_stderr = stderr.split("\n").reject { |line| line.include?(': warning:') }

        expect(non_warning_testing_stderr).to be_empty, "STDOUT:`#{stdout}` STDERR:`#{stderr}"
      end
    ) do
      at_exit(&expectations)

      # NB: This is needed because we want to patch within a forked process.
      if Datadog::Tracing::Contrib::Sidekiq::Patcher.instance_variable_get(:@patch_only_once)
        Datadog::Tracing::Contrib::Sidekiq::Patcher
          .instance_variable_get(:@patch_only_once)
          .send(:reset_ran_once_state_for_tests)
      end

      require 'sidekiq/cli'

      configure_sidekiq

      Thread.new do
        cli = Sidekiq::CLI.instance
        cli.parse(['--require', app_tempfile.path]) # boot the "app"
        cli.run
      end

      sleep duration
      exit
    end
  ensure
    app_tempfile.close
    app_tempfile.unlink
  end
end
