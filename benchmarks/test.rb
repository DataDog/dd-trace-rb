require 'ruby-prof'

require 'bundler/setup'
require 'rails/all'
Bundler.require(*Rails.groups)

module SampleApp
  class Application < Rails::Application
    # config.load_defaults 5.2
  end
end

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
end

Rails.application.initialize!

Sidekiq.server_middleware
Sidekiq.configure_server do |config|
  redis_conn = proc { Redis.new(host: 'localhost', port: 6379) }
  config.redis = ConnectionPool.new(size: 27, timeout: 3, &redis_conn)
end

require 'sidekiq/launcher'
require 'sidekiq/cli'
require 'concurrent/atomic/atomic_fixnum'

require 'ddtrace'

# WIP
class HardWorker
  class << self
    attr_reader :num
  end

  @num = Concurrent::AtomicFixnum.new(0)

  include Sidekiq::Worker
  def perform(name, count)
    self.class.num.increment
  end
end

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

options = Sidekiq.options
options[:tag] = 'test'
options[:queues] << 'default'
options[:concurrency] = 2
options[:timeout] = 2

1000.times do |i|
  HardWorker.perform_async('bob'.freeze, i)
end

# require 'ruby-prof'

# profile the code

RubyProf.start

launcher = Sidekiq::Launcher.new(options)
launcher.run

sleep(0.01) while HardWorker.num.value < 1000

result = RubyProf.stop
result.exclude_common_methods!

# print a flat profile to text
printer = RubyProf::GraphHtmlPrinter.new(result)
printer.print(STDERR)
