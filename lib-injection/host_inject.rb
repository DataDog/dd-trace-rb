return if ENV["DD_TRACE_SKIP_LIB_INJECTION"] == "true"

Gem.paths = {
  "GEM_PATH" => "/opt/datadog/apm/library/ruby/#{RUBY_VERSION.split(".")[0..1].join(".")}:/opt/datadog/apm/library/ruby:#{ENV["GEM_PATH"]}"
}

ENV["GEM_PATH"] = Gem.path.join(":")

begin
  require "open3"
  require "bundler"
  require "shellwords"
  require "fileutils"

  failure_prefix = "Datadog lib injection failed:"
  support_message = "For help solving this issue, please contact Datadog support at https://docs.datadoghq.com/help/."

  unless Bundler::SharedHelpers.in_bundle?
    STDOUT.puts "[ddtrace] Not in bundle... skipping host injection" if ENV["DD_TRACE_DEBUG"] == "true"
    return
  end

  if Bundler.frozen_bundle?
    warn "[ddtrace] #{failure_prefix} Cannot inject with frozen Gemfile, run `bundle config unset deployment` to allow lib injection. To learn more about bundler deployment, check https://bundler.io/guides/deploying.html#deploying-your-application. #{support_message}"
    return
  end

  _, status = Open3.capture2e({"DD_TRACE_SKIP_LIB_INJECTION" => "true"}, "bundle show ddtrace")

  if status.success?
    STDOUT.puts "[ddtrace] ddtrace already installed... skipping host injection" if ENV["DD_TRACE_DEBUG"] == "true"
    return
  end

  # lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile))
  lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file("/opt/datadog/apm/library/ruby/Gemfile.lock"))
  gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
    hash[spec.name] = spec.version.to_s
    hash
  end

  [
    "msgpack",
    "ffi",
    "debase-ruby_core_source",
    "libdatadog",
    "libddwaf",
    "ddtrace"
  ].each do |g|
    _, status = Open3.capture2e({"DD_TRACE_SKIP_LIB_INJECTION" => "true"}, "bundle show #{g}")
    if status.success?
      STDOUT.puts "[ddtrace] #{g} already installed... skipping..." if ENV["DD_TRACE_DEBUG"] == "true"
      next
    else
      bundle_add_cmd = "bundle add #{g} --skip-install --version #{gem_version_mapping[g]} "

      if g == "ddtrace"
        bundle_add_cmd << "--require ddtrace/auto_instrument"
      end

      STDOUT.puts "[ddtrace] Performing lib injection with `#{bundle_add_cmd}`" if ENV["DD_TRACE_DEBUG"] == "true"

      gemfile = Bundler::SharedHelpers.default_gemfile
      lockfile = Bundler::SharedHelpers.default_lockfile

      datadog_gemfile = gemfile.dirname + "datadog-Gemfile"
      datadog_lockfile = lockfile.dirname + "datadog-Gemfile.lock"

      begin
        # Copies for trial
        FileUtils.cp gemfile, datadog_gemfile
        FileUtils.cp lockfile, datadog_lockfile

        output, status = Open3.capture2e(
          {"DD_TRACE_SKIP_LIB_INJECTION" => "true", "BUNDLE_GEMFILE" => datadog_gemfile.to_s},
          bundle_add_cmd
        )

        if status.success?
          STDOUT.puts "[ddtrace] Datadog lib injection successfully added #{g} to the application."

          FileUtils.cp datadog_gemfile, gemfile
          FileUtils.cp datadog_lockfile, lockfile
        else
          warn "[ddtrace] #{failure_prefix} Unable to add ddtrace. Error output:\n#{output.split("\n").map { |l| "[ddtrace] #{l}" }.join("\n")}\n#{support_message}"
        end
      ensure
        # Remove the copies
        FileUtils.rm datadog_gemfile
        FileUtils.rm datadog_lockfile
      end

    end
  end
rescue Exception => e
  warn "[ddtrace] #{failure_prefix} #{e.class.name} #{e.message}\nBacktrace: #{e.backtrace.join("\n")}\n#{support_message}"
end
