require 'rack'
require 'json'

require_relative 'sidekiq_background_job'

module Acme
  class Application
    def call(env)
      request = Rack::Request.new(env)
      router.route!(request)
    end

    def router
      Router.new(
        '/' => { controller: controllers[:health], action: :check },
        '/health' => { controller: controllers[:health], action: :check },
        '/health/detailed' => { controller: controllers[:health], action: :detailed_check },
        '/basic/fibonacci' => { controller: controllers[:basic], action: :fibonacci },
        '/basic/default' => { controller: controllers[:basic], action: :default },
        '/background_jobs/read_sidekiq' => { controller: controllers[:background_jobs], action: :read_sidekiq },
        '/background_jobs/write_sidekiq' => { controller: controllers[:background_jobs], action: :write_sidekiq },
      )
    end

    def controllers
      {
        basic: Controllers::Basic.new,
        health: Controllers::Health.new,
        background_jobs: Controllers::BackgroundJobs.new,
      }
    end
  end

  class Router
    attr_reader :routes

    def initialize(routes)
      @routes = routes
    end

    def route!(request)
      begin
        if route = routes[request.path]
          route[:controller].send(route[:action], request)
        else
          not_found(request)
        end
      rescue StandardError => e
        application_error(request, e)
      end
    end

    def not_found(request)
      [404, { 'Content-Type' => 'text/plain' }, ["404 Not Found: #{request.path}"]]
    end

    def application_error(request, error)
      [500, { 'Content-Type' => 'text/plain' }, ["500 Application Error: #{error.message} Location: #{error.backtrace.first(3)}"]]
    end
  end

  module Controllers
    class Basic
      def fibonacci(request)
        n = rand(25..35)
        result = fib(n)
        ['200', { 'Content-Type' => 'text/plain' }, ["Basic: Fibonacci(#{n}): #{result}"]]
      end

      def default(request)
        ['200', { 'Content-Type' => 'text/plain' }, ["Basic: Default", "\nWebserver process: #{$PROGRAM_NAME}"]]
      end

      private

      def fib(n)
        n <= 1 ? n : fib(n-1) + fib(n-2)
      end
    end

    class Health
      def check(request)
        ['204', {}, []]
      end

      def detailed_check(request)
        ['200', { 'Content-Type' => 'application/json'}, [JSON.pretty_generate(
          webserver_process: $PROGRAM_NAME,
          profiler_available: !!Datadog.profiler,
          profiler_threads: Thread.list.map(&:name).filter { |it| it && it.include?('Profiling') }
        )], "\n"]
      end
    end

    class BackgroundJobs
      def read_sidekiq(request)
        ['200', { 'Content-Type' => 'text/plain' }, [SidekiqBackgroundJob.read(request.params.fetch('key')).inspect, "\n"]]
      end

      def write_sidekiq(request)
        SidekiqBackgroundJob.async_write(request.params.fetch('key'), request.params.fetch('value'))

        ['202', {}, []]
      end
    end
  end
end
