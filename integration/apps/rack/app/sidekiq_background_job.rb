require 'redis'
require 'sidekiq'
require 'json'

# To exercise sidekiq, this class allows us to write some key and value to redis asynchronously (in a background job)
# and to read it synchronously (so we can return its value easily in a web request).
# This way we can simulate the full cycle of submitting something to sidekiq, having it be executed, and its result be
# observable.
class SidekiqBackgroundJob
  include Sidekiq::Worker

  REDIS = Redis.new(url: ENV.fetch('REDIS_URL'))

  def self.read(key)
    REDIS.get("sidekiq-background-job-key-#{key}")
  end

  def self.async_write(key, value)
    perform_async(key, value)
  end

  def perform(key, value)
    puts "SidekiqBackgroundJob#perform(#{key}, #{value})"

    REDIS.set("sidekiq-background-job-key-#{key}", JSON.pretty_generate(
      key: key,
      value: value,
      sidekiq_process: $PROGRAM_NAME,
      profiler_available: Datadog::Profiling.start_if_enabled,
      profiler_threads: Thread.list.map(&:name).select { |it| it && it.include?('Profiling') },
    ))
  end
end
