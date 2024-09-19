if ENV['DD_TRACE_SKIP_LIB_INJECTION'] == 'true'
  # Skip
else
  utils = Module.new do
    module_function

    def debug(msg)
      $stdout.puts "[datadog][#{pid}][#{$0}] #{msg}" if ENV['DD_TRACE_DEBUG'] == 'true'
    end

    def error(msg)
      warn "[datadog][#{pid}][#{$0}] #{msg}"
    end

    def pid
      Process.respond_to?(:pid) ? Process.pid : 0
    end

    def root
      File.expand_path(File.join(File.dirname(__FILE__), '.'))
    end

    def path
      major, minor, = RUBY_VERSION.split('.')
      ruby_api_version = "#{major}.#{minor}.0"

      "#{root}/#{ruby_api_version}"
    end

    def version
      File.exist?("#{root}/version") ? File.read("#{root}/version").chomp : 'unknown'
    end
  end

  telemetry = Module.new do
    module_function

    def emit(pid, version, events)
      payload = {
        metadata: {
          language_name: 'ruby',
          language_version: RUBY_VERSION,
          runtime_name: RUBY_ENGINE,
          runtime_version: RUBY_VERSION,
          tracer_version: version,
          pid: pid
        },
        points: events
      }

      fowarder = ENV['DD_TELEMETRY_FORWARDER_PATH']

      if fowarder && !fowarder.empty?
        require 'open3'
        require 'json'

        Open3.capture2e([fowarder, 'library_entrypoint'], stdin_data: payload.to_json)
      end
    end
  end

  pid = utils.pid

  if Process.respond_to?(:fork)
    utils.debug 'Starts injection'

    require 'rubygems'

    read, write = IO.pipe

    fork do
      read.close

      require 'open3'
      require 'bundler'
      require 'bundler/cli'
      require 'fileutils'

      precheck = Module.new do
        module_function

        def in_bundle?
          Bundler::SharedHelpers.in_bundle?
        end

        def runtime_supported?
          major, minor, = RUBY_VERSION.split('.')
          ruby_api_version = "#{major}.#{minor}.0"

          supported_ruby_api_versions = ['2.7.0', '3.0.0', '3.1.0', '3.2.0'].freeze

          RUBY_ENGINE == 'ruby' && supported_ruby_api_versions.any? { |v| ruby_api_version == v }
        end

        def platform_supported?
          platform_support_matrix = {
            cpu: ['x86_64', 'aarch64'].freeze,
            os: ['linux'].freeze,
            version: ['gnu', nil].freeze # nil is equivalent to `gnu` for local platform
          }
          local_platform = Gem::Platform.local

          platform_support_matrix.fetch(:cpu).any? { |v| local_platform.cpu == v } &&
            platform_support_matrix.fetch(:os).any? { |v| local_platform.os == v } &&
            platform_support_matrix.fetch(:version).any? { |v| local_platform.version == v }
        end

        def already_installed?
          ['ddtrace', 'datadog'].any? do |gem|
            fork do
              $stdout = File.new('/dev/null', 'w')
              $stderr = File.new('/dev/null', 'w')
              Bundler::CLI::Common.select_spec(gem)
            end
            _, status = Process.wait2
            status.success?
          end
        end

        def frozen_bundle?
          Bundler.frozen_bundle?
        end

        def bundler_supported?
          Bundler::CLI.commands['add'] && Bundler::CLI.commands['add'].options.key?('require')
        end
      end

      if !precheck.in_bundle?
        utils.debug 'Not in bundle... skipping injection'
        exit!(1)
      elsif !precheck.runtime_supported?
        utils.debug "Runtime not supported: #{RUBY_DESCRIPTION}"
        telemetry.emit(
          pid,
          utils.version,
          [{ name: 'library_entrypoint.abort', tags: ['reason:incompatible_runtime'] },
           { name: 'library_entrypoint.abort.runtime' }]
        )
        exit!(1)
      elsif !precheck.platform_supported?
        utils.debug "Platform not supported: #{local_platform}"
        telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.abort', tags: ['reason:incompatible_platform'] }])
        exit!(1)
      elsif precheck.already_installed?
        utils.debug 'Skip injection: already installed'
      elsif precheck.frozen_bundle?
        utils.error "Skip injection: bundler is configured with 'deployment' or 'frozen'"
        telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.abort', tags: ['reason:bundler'] }])
        exit!(1)
      elsif !precheck.bundler_supported?
        utils.error "Skip injection: bundler version #{Bundler::VERSION} is not supported, please upgrade to >= 2.3."
        telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.abort', tags: ['reason:bundler_version'] }])
        exit!(1)
      else
        # Injection
        path = utils.path
        utils.debug "Loading from #{path}"
        lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file("#{path}/Gemfile.lock"))
        gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
          hash[spec.name] = spec.version.to_s
          hash
        end

        gemfile = Bundler::SharedHelpers.default_gemfile
        lockfile = Bundler::SharedHelpers.default_lockfile

        datadog_gemfile = gemfile.dirname + '.datadog-Gemfile'
        datadog_lockfile = lockfile.dirname + '.datadog-Gemfile.lock'

        # Copies for trial
        ::FileUtils.cp gemfile, datadog_gemfile
        ::FileUtils.cp lockfile, datadog_lockfile

        injection_failure = false

        # This is order dependent
        [
          'msgpack',
          'ffi',
          'debase-ruby_core_source',
          'libdatadog',
          'libddwaf',
          'datadog'
        ].each do |gem|
          fork do
            $stdout = File.new('/dev/null', 'w')
            $stderr = File.new('/dev/null', 'w')
            Bundler::CLI::Common.select_spec(gem)
          end

          _, status = Process.wait2
          if status.success?
            utils.debug "#{gem} already installed... skipping..."
            next
          end

          bundle_add_cmd = "bundle add #{gem} --skip-install --version #{gem_version_mapping[gem]} "
          bundle_add_cmd << ' --verbose ' if ENV['DD_TRACE_DEBUG'] == 'true'
          bundle_add_cmd << '--require datadog/auto_instrument' if gem == 'datadog'

          utils.debug "Injection with `#{bundle_add_cmd}`"

          env = { 'BUNDLE_GEMFILE' => datadog_gemfile.to_s,
                  'DD_TRACE_SKIP_LIB_INJECTION' => 'true',
                  'GEM_PATH' => utils.path }
          add_output, add_status = Open3.capture2e(env, bundle_add_cmd)

          if add_status.success?
            utils.debug "Successfully injected #{gem} into the application."
          else
            injection_failure = true
            utils.error "Injection failed: Unable to add datadog. Error output: #{add_output}"
          end
        end

        if injection_failure
          ::FileUtils.rm datadog_gemfile
          ::FileUtils.rm datadog_lockfile
          telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.error', tags: ['error_type:injection_failure'] }])
          exit!(1)
        else
          write.puts datadog_gemfile.to_s
          telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.complete', tags: ['injection_forced:false'] }])
        end
      end
    end

    write.close
    gemfile = read.read.to_s.chomp

    _, status = Process.wait2
    ENV['DD_TRACE_SKIP_LIB_INJECTION'] = 'true'

    if status.success?
      dd_lib_injection_path = utils.path

      Gem.paths = { 'GEM_PATH' => "#{dd_lib_injection_path}:#{ENV['GEM_PATH']}" }
      ENV['GEM_PATH'] = Gem.path.join(':')
      ENV['BUNDLE_GEMFILE'] = gemfile
      utils.debug "Fork success: Using Gemfile `#{gemfile}`"
    else
      utils.debug 'Fork abort'
    end
  else
    utils.debug 'Fork not supported... skipping injection'
    telemetry.emit(pid, utils.version, [{ name: 'library_entrypoint.abort', tags: ['reason:fork_not_supported'] }])
  end
end
