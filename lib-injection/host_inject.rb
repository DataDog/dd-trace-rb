# Keep in sync with auto_inject.rb

return if ENV['DD_TRACE_SKIP_LIB_INJECTION'] == 'true'

require 'rubygems'
require 'rbconfig'

ruby_api_version = RbConfig::CONFIG['ruby_version']

dd_lib_injection_path = "/opt/datadog/apm/library/ruby/#{ruby_api_version}"

# Look for pre-installed tracers
Gem.paths = {
  'GEM_PATH' => "#{dd_lib_injection_path}:#{ENV['GEM_PATH']}"
}

# Also apply to the environment variable, to guarantee any spawned processes will respected the modified `GEM_PATH`.
ENV['GEM_PATH'] = Gem.path.join(':')

def debug_log(msg)
  $stdout.puts msg if ENV['DD_TRACE_DEBUG'] == 'true'
end

begin
  require 'open3'
  require 'bundler'
  require 'bundler/cli'
  require 'shellwords'
  require 'fileutils'

  support_message = 'For help solving this issue, please contact Datadog support at https://docs.datadoghq.com/help/.'

  unless Bundler::SharedHelpers.in_bundle?
    debug_log '[ddtrace] Not in bundle... skipping injection'
    return
  end

  _, status = Open3.capture2e({ 'DD_TRACE_SKIP_LIB_INJECTION' => 'true' }, 'bundle show ddtrace')
  if status.success?
    debug_log '[ddtrace] ddtrace already installed... skipping injection'
    return
  end

  if Bundler.frozen_bundle?
    warn '[ddtrace] Injection failed: Unable to inject into a frozen Gemfile '\
    '(Bundler is configured with `deployment` or `frozen`)'
    return
  end

  unless Bundler::CLI.commands['add'] && Bundler::CLI.commands['add'].options.key?('require')
    warn "[ddtrace] Injection failed: Bundler version #{Bundler::VERSION} is not supported. "\
      'Upgrade to Bundler >= 2.3 to enable injection.'
    return
  end

  lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file("#{dd_lib_injection_path}/Gemfile.lock"))
  gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
    hash[spec.name] = spec.version.to_s
    hash
  end

  # This is order dependent
  [
    'msgpack',
    'ffi',
    'datadog-ruby_core_source',
    'libdatadog',
    'libddwaf',
    'datadog-ci',
    'ddtrace'
  ].each do |gem|
    _, status = Open3.capture2e({ 'DD_TRACE_SKIP_LIB_INJECTION' => 'true' }, "bundle show #{gem}")

    if status.success?
      debug_log "[ddtrace] #{gem} already installed... skipping..."
      next
    else
      bundle_add_cmd = "bundle add #{gem} --skip-install --version #{gem_version_mapping[gem]} "

      bundle_add_cmd << '--require ddtrace/auto_instrument' if gem == 'ddtrace'

      debug_log "[ddtrace] Injection with `#{bundle_add_cmd}`"

      gemfile = Bundler::SharedHelpers.default_gemfile
      lockfile = Bundler::SharedHelpers.default_lockfile

      datadog_gemfile = gemfile.dirname + 'datadog-Gemfile'
      datadog_lockfile = lockfile.dirname + 'datadog-Gemfile.lock'

      begin
        # Copies for trial
        ::FileUtils.cp gemfile, datadog_gemfile
        ::FileUtils.cp lockfile, datadog_lockfile

        output, status = Open3.capture2e(
          { 'DD_TRACE_SKIP_LIB_INJECTION' => 'true', 'BUNDLE_GEMFILE' => datadog_gemfile.to_s },
          bundle_add_cmd
        )

        if status.success?
          $stdout.puts "[ddtrace] Successfully injected #{gem} into the application."

          ::FileUtils.cp datadog_gemfile, gemfile
          ::FileUtils.cp datadog_lockfile, lockfile
        else
          warn "[ddtrace] Injection failed: Unable to add ddtrace. Error output:\n#{output.split("\n").map do |l|
            "[ddtrace] #{l}"
          end.join("\n")}\n#{support_message}"
        end
      ensure
        # Remove the copies
        ::FileUtils.rm datadog_gemfile
        ::FileUtils.rm datadog_lockfile
      end
    end
  end
rescue Exception => e
  warn "[ddtrace] Injection failed: #{e.class.name} #{e.message}\nBacktrace: #{e.backtrace.join("\n")}\n#{support_message}"
end
