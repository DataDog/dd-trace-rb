require_relative './environment'
require 'datadog/demo_env'

Datadog::DemoEnv.print_env('Puma master environment')

workers ENV.fetch("WEB_CONCURRENCY") { 1 }

max_threads_count = ENV.fetch("HANAMI_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("HANAMI_MIN_THREADS") { max_threads_count }

threads max_threads_count, min_threads_count

preload_app!

port ENV.fetch("PORT") { 80 }

environment ENV.fetch("HANAMI_ENV") { "development" }

on_worker_boot do
  Hanami.boot
end
