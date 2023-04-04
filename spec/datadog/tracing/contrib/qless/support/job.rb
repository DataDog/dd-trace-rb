LogHelpers.without_warnings do
  require 'qless'
end

require 'datadog/tracing/contrib/qless/qless_job'
require 'qless'
require 'qless/test_helpers/worker_helpers'
require 'qless/worker'
require 'qless/job_reservers/ordered'

### For ForkingWorker
require 'qless/job_reservers/round_robin'
require 'tempfile'

class TempfileWithString < Tempfile
  # To mirror StringIO#string
  def string
    rewind
    read.tap { close }
  end
end

RSpec.shared_context 'Qless job' do
  include Qless::WorkerHelpers

  let(:host) { ENV.fetch('TEST_REDIS_OLD_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_OLD_PORT', '6379') }

  let(:client) { Qless::Client.new(host: host, port: port) }
  let(:queue) { client.queues['main'] }
  let(:reserver) { Qless::JobReservers::Ordered.new([queue]) }

  let(:log_io) { TempfileWithString.new('qless.log') }
  let(:worker) do
    Qless::Workers::ForkingWorker.new(
      Qless::JobReservers::RoundRobin.new([queue]),
      interval: 1,
      max_startup_interval: 0,
      output: log_io,
      log_level: Logger::DEBUG
    )
  end

  after { log_io.unlink }

  def perform_job(klass, *args)
    queue.put(klass, args)
    drain_worker_queues(worker)
  end

  def failed_jobs
    client.jobs.failed
  end

  def delete_all_redis_keys
    # rubocop:disable Style/HashEachMethods
    # This LOOKS like a Ruby hash but ISN'T -- so it doesn't have the `each_key` method that Rubocop suggests
    client.redis.keys.each { |k| client.redis.del k }
  end

  let(:job_class) do
    stub_const('TestJob', Class.new).tap do |mod|
      mod.send(:define_singleton_method, :perform) do |job|
        # Do nothing by default.
      end
    end
  end
  let(:job_args) { {} }
end
