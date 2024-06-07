require 'redis'
require 'resque'
require 'json'

Resque.redis = Redis.new(url: ENV.fetch('REDIS_URL'))

# To exercise resque, this class allows us to write some key and value to redis asynchronously (in a background job)
# and to read it synchronously (so we can return its value easily in a web request).
# This way we can simulate the full cycle of submitting something to resque, having it be executed, and its result be
# observable.
class ResqueBackgroundJob
  REDIS = Redis.new(url: ENV.fetch('REDIS_URL'))

  @queue = :resque_testing

  def self.read(key)
    REDIS.get("resque-background-job-key-#{key}")
  end

  def self.async_write(key, value)
    Resque.enqueue(self, key, value)
  end

  def self.perform(key, value)
    puts "ResqueBackgroundJob#perform(#{key}, #{value})"

    REDIS.set("resque-background-job-key-#{key}", JSON.pretty_generate(
      key: key,
      value: value,
      resque_process: $PROGRAM_NAME,
      profiler_available: Datadog::Profiling.start_if_enabled,
      profiler_threads: Thread.list.map(&:name).select { |it| it && it.include?('Profiling') },
    ))
  end
end
