ENV['RAILS_ENV'] = 'production'
require 'English'

# Benchmark Configuration container
module TestConfiguration
  module_function

  def sidekiq
    Sidekiq.options.tap do |options|
      options[:tag] = 'test'
      options[:queues] << 'default'
      options[:concurrency] = 20
      options[:timeout] = 2
    end
  end

  def redis
    { pool_size: 30, timeout: 3 }
  end

  def iteration_count
    1000
  end
end

require 'bundler/setup'
require 'rails/all'
Bundler.require(*Rails.groups)

# Example Rails App
module SampleApp
  class Application < Rails::Application; end
end

# Overrides rails configueration locations
module OverrideConfiguration
  def paths
    super.tap { |path| path.add 'config/database', with: 'benchmarks/postgres_database.yml' }
  end
end

Rails::Application::Configuration.prepend(OverrideConfiguration)

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.active_job.queue_adapter = :sidekiq
end

ActiveRecord::Base.configurations = Rails.application.config.database_configuration
Rails.application.initialize!

ActiveRecord::Schema.define do
  drop_table(:samples) if connection.table_exists?(:samples)

  create_table :samples do |t|
    t.string :name
    t.timestamps
  end
end

class Sample < ActiveRecord::Base; end

require 'sidekiq/launcher'
require 'sidekiq/cli'
require 'concurrent/atomic/atomic_fixnum'

Sidekiq.configure_server do |config|
  redis_conn = proc do
    Redis.new(
      host: ENV.fetch('TEST_REDIS_HOST', '127.0.0.1'),
      port: ENV.fetch('TEST_REDIS_PORT', 6379)
    )
  end
  config.redis = ConnectionPool.new(size: TestConfiguration.redis[:pool_size],
                                    timeout: TestConfiguration.redis[:timeout],
                                    &redis_conn)
end

# Simple Sidekiq worker performing the real benchmark
class Worker
  class << self
    attr_reader :iterations, :conditional_variable
  end

  @iterations = Concurrent::AtomicFixnum.new(0)
  @conditional_variable = ConditionVariable.new

  include Sidekiq::Worker
  def perform(iter, max_iterations)
    self.class.iterations.increment
    self.class.conditional_variable.broadcast if self.class.iterations.value > max_iterations

    Sample.create!(name: iter.to_s).save

    100.times do
      Sample.last.name
    end

    Sample.last(100).to_a
  end
end


Datadog.configure do |d|
  d.instrument :rails, enabled: true, tags: { 'tag' => 'value' }
  d.instrument :http
  d.instrument :sidekiq, service_name: 'service'
  d.instrument :redis
  d.instrument :dalli
  d.instrument :resque, workers: [Worker]

  processor = Datadog::Pipeline::SpanProcessor.new do |span|
    true if span.service == 'B'
  end

  Datadog::Tracing.before_flush(processor)
end

def current_memory
  `ps -o rss #{$PROCESS_ID}`.split("\n")[1].to_f / 1024
end

def time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def launch(iterations, options)
  iterations.times do |i|
    Worker.perform_async(i, iterations)
  end

  launcher = Sidekiq::Launcher.new(options)
  launcher.run
end

def wait_and_measure(iterations)
  start = time

  STDERR.puts "#{time - start}, #{current_memory}"

  mutex = Mutex.new

  while Worker.iterations.value < iterations
    mutex.synchronize do
      Worker.conditional_variable.wait(mutex, 1)
      STDERR.puts "#{time - start}, #{current_memory}"
    end
  end
end

launch(TestConfiguration.iteration_count, TestConfiguration.sidekiq)
wait_and_measure(TestConfiguration.iteration_count)
