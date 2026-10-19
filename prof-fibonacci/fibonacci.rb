require 'grape'
require 'active_support/cache'
require 'datadog/auto_instrument'
require 'open-uri'

Datadog.configure do |c|
  c.tracing.instrument :grape, service_name: c.service
  c.runtime_metrics.enabled = true
end

module Fib
  # Bounded cache for string garbage to increase GC overhead
  STRING_CACHE_SIZE = 10000
  @@string_cache = []
  @@cache_index = 0

  def self.create_garbage_strings(count = 3)
    count.times do |i|
      # Create various types of strings to simulate real-world string allocation
      garbage_string = "fibonacci_computation_iteration_#{i}"
      
      # Add to bounded cache
      if @@string_cache.size < STRING_CACHE_SIZE
        @@string_cache << garbage_string
      else
        # Replace old entries in a circular fashion
        @@string_cache[@@cache_index] = garbage_string
        @@cache_index = (@@cache_index + 1) % STRING_CACHE_SIZE
      end
    end
  end

  def self.fib(n)
    # Create garbage strings during computation to increase GC overhead
    create_garbage_strings
    n <= 1 ? n : fib(n-1) + fib(n-2)
  end

  def self.compute(n)
    fib(n)
  end

  def self.compute_twice(n)
    2.times { fib(n) }
  end

  def self.compute_thrice(n)
    3.times { fib(n) }
  end

  def self.compute_negative(n)
    -fib(n)
  end

  def self.compute_emoji(n)
    emoji = %w(🤔 👌 🌈 🐟 🌊 ⭐️ 💪)
    res = fib(n) % emoji.size
    emoji[res]
  end
end

class FibServer < Grape::API
  format :json

  resource :fib do
    params { requires :n, type: Integer }
    route_param :n do
      get(:compute) { Fib.compute(params.fetch(:n)) }
      get(:compute_twice) { Fib.compute_twice(params.fetch(:n)) }
      get(:compute_thrice) { Fib.compute_thrice(params.fetch(:n)) }
      get(:compute_negative) { Fib.compute_negative(params.fetch(:n)) }
      get(:compute_emoji) { Fib.compute_emoji(params.fetch(:n)) }
    end
  end
end

class FibClient
  ENDPOINTS = [:compute, :compute_twice, :compute_thrice, :compute_negative, :compute_emoji]

  def fib_request
    GC.start
    URI.open("http://127.0.0.1:8080/fib/#{rand(26..36)}/#{ENDPOINTS.sample.to_s}/")
    sleep 0.1
  rescue => e
    puts "Request failed: #{e.message}"
    sleep 0.1
  end

  def wait_for_webserver
    fib_request
    puts "Web server started!"
  rescue Errno::ECONNREFUSED
    print '.'
    retry
  end

  def start
    2.times do |i|
      Thread.new do
        puts "Spinning up worker #{i}"
        Thread.current.name = "Request load generator - #{i}"
        wait_for_webserver

        puts "Workload generator started!"
        loop { fib_request }
      end
    end
  end
end
