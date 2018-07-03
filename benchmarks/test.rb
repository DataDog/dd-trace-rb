# rubocop:disable all
require 'ruby-prof'

require 'bundler/setup'
require 'rails/all'

ENV['RAILS_ENV'] = 'production'

class Rails::Application::Configuration
  def database_configuration
    {
        'production' => {
          adapter: 'postgresql',
          timeout: 5000,
          database: ENV.fetch('TEST_POSTGRES_DB', 'postgres'),
          host: ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1'),
          port: ENV.fetch('TEST_POSTGRES_PORT', 5432),
          username: ENV.fetch('TEST_POSTGRES_USER', 'postgres'),
          password: ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres'),

          pool: 30
        }
    }
  end
end

Bundler.require(*Rails.groups)

module SampleApp
  class Application < Rails::Application; end
end

ActiveRecord::Base.configurations = Rails.application.config.database_configuration

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.active_job.queue_adapter = :sidekiq
end

Rails.application.initialize!
ActiveRecord::Base.connection_config

ActiveRecord::Schema.define do
  drop_table(:samples) if connection.table_exists?(:samples)

  create_table :samples do |t|
    t.string :name
    t.timestamps
  end
end

Sidekiq.server_middleware
Sidekiq.configure_server do |config|
  redis_conn = proc { Redis.new(host: 'localhost', port: 6379) }
  config.redis = ConnectionPool.new(size: 27, timeout: 3, &redis_conn)
end

class Sample < ActiveRecord::Base; end

require 'sidekiq/launcher'
require 'sidekiq/cli'
require 'concurrent/atomic/atomic_fixnum'

# require 'ddtrace'

# WIP
class HardWorker
  class << self
    attr_reader :num
  end

  @num = Concurrent::AtomicFixnum.new(0)

  include Sidekiq::Worker
  def perform(name, count)
    self.class.num.increment
    Sample.create!(name: name).save
    Sample.last
  end
end

if Datadog.respond_to?(:configure)
Datadog.configure do |d|
  d.use :rails,
        enabled: true,
        auto_instrument: true,
        auto_instrument_redis: true,
        service_name: 'A',
        controller_service: 'B',
        database_service: 'C',
        cache_service: 'D',
        tags: { 'dyno' => 'dyno' }

  d.use :resque, workers: [HardWorker]
  d.use :sidekiq, service_name: 'E'
  d.use :aws
  d.use :dalli
  d.use :http
  d.use :redis

  SERVICE_MAPPING = {
    /^ServiceA::/ => 'service_a',
    /^ServiceB::/ => 'service_b',
    /^ServiceC::/ => 'service_c',
    /^ServiceD::/ => 'service_d'
  }.freeze
  processor = Datadog::Pipeline::SpanProcessor.new do |span|
    if span.service == 'B'
      SERVICE_MAPPING.any? do |pattern, service_suffix|
        if span.resource =~ pattern
          span.service = "APP-#{service_suffix}"
          true
        end
      end
    end
  end

  Datadog::Pipeline.before_flush(processor)
end
end

def memory
  `ps -o rss #{$$}`.split("\n")[1].to_f/1024
end

def time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

start = time
STDERR.puts "#{time-start}, #{memory}"


options = Sidekiq.options
options[:tag] = 'test'
options[:queues] << 'default'
options[:concurrency] = 20
options[:timeout] = 2

num = 10000

num.times do |i|
  HardWorker.perform_async('bob'.freeze, i)
end



# RubyProf.start

launcher = Sidekiq::Launcher.new(options)
launcher.run

while HardWorker.num.value < num
  sleep(1)
  STDERR.puts "#{time-start}, #{memory}"
end

# sleep(1) while HardWorker.num.value < 1000

# result = RubyProf.stop
# result.exclude_common_methods!

# print a flat profile to text
# printer = RubyProf::GraphHtmlPrinter.new(result)
# printer.print(STDERR)
