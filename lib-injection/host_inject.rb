return if ENV["DD_TRACE_SKIP_LIB_INJECTION"] == "true"
require "rubygems"

# This would return MAJOR.MINOR without PATCH version, for example 3.1, 3.2
ruby_version = RUBY_VERSION.split(".")[0..1].join(".")

# Look for pre-installed tracers
Gem.paths = {
  "GEM_PATH" => "/opt/datadog/apm/library/ruby/#{ruby_version}:/opt/datadog/apm/library/ruby:#{ENV["GEM_PATH"]}"
}

ENV["GEM_PATH"] = Gem.path.join(":")

def debug_log(msg)
  STDOUT.puts msg if ENV["DD_TRACE_DEBUG"] == "true"
end

begin
  require "open3"
  require "bundler"
  require "bundler/cli"
  require "shellwords"
  require "fileutils"

  failure_prefix = "Datadog lib injection failed:"
  support_message = "For help solving this issue, please contact Datadog support at https://docs.datadoghq.com/help/."

  unless Bundler::SharedHelpers.in_bundle?
    debug_log "[ddtrace] Not in bundle... skipping host injection"
    return
  end

  unless Bundler::CLI.commands["add"] && Bundler::CLI.commands["add"].options.key?("require")
    debug_log "[ddtrace] You are currently using Bundler version #{Bundler::VERSION} which is not supported by host injection. Please upgrade >= 2.3, check https://github.com/rubygems/rubygems/blob/master/bundler/CHANGELOG.md#enhancements-31"
    return
  end

  if Bundler.frozen_bundle?
    warn "[ddtrace] #{failure_prefix} Cannot inject with frozen Gemfile, run `bundle config unset deployment` to allow lib injection. To learn more about bundler deployment, check https://bundler.io/guides/deploying.html#deploying-your-application. #{support_message}"
    return
  end

  _, status = Open3.capture2e({"DD_TRACE_SKIP_LIB_INJECTION" => "true"}, "bundle show ddtrace")

  if status.success?
    debug_log "[ddtrace] ddtrace already installed... skipping host injection"
    return
  end

  lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file("/opt/datadog/apm/library/ruby/Gemfile.lock"))
  gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
    hash[spec.name] = spec.version.to_s
    hash
  end

  # This is order dependent
  [
    "msgpack",
    "ffi",
    "debase-ruby_core_source",
    "libdatadog",
    "libddwaf",
    "ddtrace"
  ].each do |gem|
    _, status = Open3.capture2e({"DD_TRACE_SKIP_LIB_INJECTION" => "true"}, "bundle show #{gem}")

    if status.success?
      debug_log "[ddtrace] #{gem} already installed... skipping..."
      next
    else
      bundle_add_cmd = "bundle add #{gem} --skip-install --version #{gem_version_mapping[gem]} "

      if gem == "ddtrace"
        bundle_add_cmd << "--require ddtrace/auto_instrument"
      end

      debug_log "[ddtrace] Performing lib injection with `#{bundle_add_cmd}`"

      gemfile = Bundler::SharedHelpers.default_gemfile
      lockfile = Bundler::SharedHelpers.default_lockfile

      datadog_gemfile = gemfile.dirname + "datadog-Gemfile"
      datadog_lockfile = lockfile.dirname + "datadog-Gemfile.lock"

      begin
        # Copies for trial
        ::FileUtils.cp gemfile, datadog_gemfile
        ::FileUtils.cp lockfile, datadog_lockfile

        output, status = Open3.capture2e(
          {"DD_TRACE_SKIP_LIB_INJECTION" => "true", "BUNDLE_GEMFILE" => datadog_gemfile.to_s},
          bundle_add_cmd
        )

        if status.success?
          STDOUT.puts "[ddtrace] Datadog lib injection successfully added #{gem} to the application."

          ::FileUtils.cp datadog_gemfile, gemfile
          ::FileUtils.cp datadog_lockfile, lockfile
        else
          warn "[ddtrace] #{failure_prefix} Unable to add ddtrace. Error output:\n#{output.split("\n").map { |l| "[ddtrace] #{l}" }.join("\n")}\n#{support_message}"
        end
      ensure
        # Remove the copies
        ::FileUtils.rm datadog_gemfile
        ::FileUtils.rm datadog_lockfile
      end

    end
  end
rescue Exception => e
  warn "[ddtrace] #{failure_prefix} #{e.class.name} #{e.message}\nBacktrace: #{e.backtrace.join("\n")}\n#{support_message}"
end
