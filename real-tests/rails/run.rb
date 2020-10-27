require 'bundler'


require 'fileutils'

def template_changed?(destination_root)
  !FileUtils.compare_file('./template.rb', File.join(destination_root, 'template.rb'))
rescue Errno::ENOENT => _
  true
end

server_pid = nil

path = Gem.bin_path("bundler", "bundle")
Bundler.with_original_env do
  ENV["BUNDLE_BIN_PATH"] = path # TODO: Why is BUNDLE_BIN_PATH butchered?

  destination_root = File.join(Dir.pwd, 'rails-app')

  if template_changed?(destination_root)
    FileUtils.rm_rf(destination_root)

    # require "rails/generators"
    # require "rails/generators/rails/app/app_generator"
    # template = './template.rb'
    # template = File.expand_path(template) if !%r{\A[A-Za-z][A-Za-z0-9+\-\.]*://}.match?(template)

    require "rails/app_loader"

    # If we are inside a Rails application this method performs an exec and thus
    # the rest of this script is not run.
    Rails::AppLoader.exec_app

    require "rails/ruby_version_check"
    Signal.trap("INT") { puts; exit(1) }

    require "rails/command"

    Rails::Command.invoke :application, ["new", "rails-app", "-m", "./template.rb", "--api", "--database=postgresql", "--skip-spring", "--skip-bootsnap", "--skip-sprockets", "--skip-keeps", "--skip-test-unit"]
    #
    # Rails::Generators::AppGenerator.start
    # # generator = Rails::Generators::AppGenerator.new [Rails.root], {}, { destination_root: Rails.root }
    # generator = Rails::Generators::AppGenerator.new [destination_root], {api: true}, { destination_root: destination_root }
    # generator.invoke
    # generator.apply template, verbose: false
  end

  FileUtils.cd(destination_root) # Only needed on cached run
  server_pid = spawn("RAILS_ENV=production bin/rails s")

  at_exit do
    Process.kill('TERM', server_pid)
    Process.wait(server_pid)
  end
end

require 'net/http'

def make_request
  Net::HTTP.get('localhost', '/', 3000)
end

# Wait for Rails
loop do
  make_request
  break
rescue Errno::ECONNREFUSED => _
  sleep 0.05
  retry
end

counter = []

requests = 300
concurrency = 4

threads = concurrency.times.map do
  Thread.new do
    (requests / concurrency).times do
      make_request
      counter << 1
    end
  end
end

puts "Process.pid: #{server_pid}"

stop_measure = false
measure_thread = Thread.new do
  interval = 5.0
  last = counter.size
  loop do
    puts "requests: #{counter.size}/#{requests} (#{(counter.size - last) / interval}/s)"
    last = counter.size
    puts 'memory: ' + `ps -o rss= -p #{server_pid}`.to_i.to_s
    sleep interval
    break if stop_measure
  end
end

require 'benchmark'

results = Benchmark.measure do
  threads.each(&:join)
end

pp results

measure_thread.kill

# apt-get update && apt-get install -y valgrind && cg_diff /mount/benchmark/profile.callgrind.out. /mount/benchmark/profile.callgrind.out.