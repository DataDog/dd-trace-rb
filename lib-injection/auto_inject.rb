return if ENV['DD_TRACE_SKIP_LIB_INJECTION'] == 'true'

begin
  require 'open3'
  support_message = 'For help solving this issue, please contact Datadog support at https://docs.datadoghq.com/help/.'

  def debug_log(msg)
    STDOUT.puts msg if ENV["DD_TRACE_DEBUG"] == "true"
  end

  _, status = Open3.capture2e({'DD_TRACE_SKIP_LIB_INJECTION' => 'true'}, 'bundle show ddtrace')
  if status.success?
    debug_log '[ddtrace] ddtrace already installed... skipping injection'
    return
  end

  require 'bundler'
  require "bundler/cli"
  require 'shellwords'

  if Bundler.frozen_bundle?
    STDERR.puts "[ddtrace] Injection failed: Unable to inject into a Frozen Gemfile (Bundler is configured with `deployment` or `frozen`)"
    return
  end

  unless Bundler::CLI.commands["add"] && Bundler::CLI.commands["add"].options.key?("require")
    STDERR.puts "[ddtrace] Injection failed: Bundler version #{Bundler::VERSION} is not supported. Please upgrade >= 2.3."
    return
  end

  # `version` and `sha` should be replaced by docker build arguments
  version = "<DD_TRACE_VERSION_TO_BE_REPLACED>"
  sha = "<DD_TRACE_SHA_TO_BE_REPLACED>"

  bundle_add_ddtrace_cmd =
    if !version.empty?
      # For public release
      "bundle add ddtrace --require ddtrace/auto_instrument --version #{version.gsub(/^v/, '').shellescape}"
    elsif !sha.empty?
      # For internal testing
      "bundle add ddtrace --require ddtrace/auto_instrument --github datadog/dd-trace-rb --ref #{sha.shellescape}"
    end

  unless bundle_add_ddtrace_cmd
    STDERR.puts "[ddtrace] Injection failed: Missing version specification. #{support_message}"
    return
  end

  debug_log "[ddtrace] Injection with `#{bundle_add_ddtrace_cmd}`"

  gemfile   = Bundler::SharedHelpers.default_gemfile
  lockfile  = Bundler::SharedHelpers.default_lockfile

  datadog_gemfile  = gemfile.dirname  + "datadog-Gemfile"
  datadog_lockfile = lockfile.dirname + "datadog-Gemfile.lock"

  require 'fileutils'

  begin
    # Copies for trial
    FileUtils.cp gemfile, datadog_gemfile
    FileUtils.cp lockfile, datadog_lockfile

    output, status = Open3.capture2e(
      { 'DD_TRACE_SKIP_LIB_INJECTION' => 'true', 'BUNDLE_GEMFILE' => datadog_gemfile.to_s },
      bundle_add_ddtrace_cmd
    )

    if status.success?
      STDOUT.puts '[ddtrace] Injection adds ddtrace to the application successfully.'

      FileUtils.cp datadog_gemfile, gemfile
      FileUtils.cp datadog_lockfile, lockfile
    else
      STDERR.puts "[ddtrace] Injection failed: Unable to add ddtrace. Error output:\n#{output.split("\n").map {|l| "[ddtrace] #{l}"}.join("\n")}\n#{support_message}"
    end
  ensure
    # Remove the copies
    FileUtils.rm datadog_gemfile
    FileUtils.rm datadog_lockfile
  end
rescue Exception => e
  STDERR.puts "[ddtrace] Injection failed: #{e.class.name} #{e.message}\nBacktrace: #{e.backtrace.join("\n")}\n#{support_message}"
end
