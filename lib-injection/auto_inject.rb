# Keep in sync with host_inject.rb

return if ENV['DD_TRACE_SKIP_LIB_INJECTION'] == 'true'

begin
  require 'open3'
  support_message = 'For help solving this issue, please contact Datadog support at https://docs.datadoghq.com/help/.'

  def debug_log(msg)
    $stdout.puts msg if ENV['DD_TRACE_DEBUG'] == 'true'
  end

  _, status = Open3.capture2e({ 'DD_TRACE_SKIP_LIB_INJECTION' => 'true' }, 'bundle show datadog')
  if status.success?
    debug_log '[datadog] datadog already installed... skipping injection'
    return
  end

  require 'bundler'
  require 'bundler/cli'
  require 'shellwords'

  if Bundler.frozen_bundle?
    warn '[datadog] Injection failed: Unable to inject into a frozen Gemfile '\
      '(Bundler is configured with `deployment` or `frozen`)'
    return
  end

  unless Bundler::CLI.commands['add'] && Bundler::CLI.commands['add'].options.key?('require')
    warn "[datadog] Injection failed: Bundler version #{Bundler::VERSION} is not supported. "\
      'Upgrade to Bundler >= 2.3 to enable injection.'
    return
  end

  # `version` and `sha` should be replaced by docker build arguments
  version = '<DATADOG_GEM_VERSION_TO_BE_REPLACED>'
  sha = '<DATADOG_GEM_SHA_TO_BE_REPLACED>'

  bundle_add_datadog_cmd =
    if !version.empty?
      # For public release
      "bundle add datadog --require datadog/auto_instrument --version #{version.gsub(/^v/, '').shellescape}"
    elsif !sha.empty?
      # For internal testing
      "bundle add datadog --require datadog/auto_instrument --github datadog/dd-trace-rb --ref #{sha.shellescape}"
    end

  unless bundle_add_datadog_cmd
    warn "[datadog] Injection failed: Missing version specification. #{support_message}"
    return
  end

  debug_log "[datadog] Injection with `#{bundle_add_datadog_cmd}`"

  gemfile   = Bundler::SharedHelpers.default_gemfile
  lockfile  = Bundler::SharedHelpers.default_lockfile

  datadog_gemfile  = gemfile.dirname  + 'datadog-Gemfile'
  datadog_lockfile = lockfile.dirname + 'datadog-Gemfile.lock'

  require 'fileutils'

  begin
    # Copies for trial
    FileUtils.cp gemfile, datadog_gemfile
    FileUtils.cp lockfile, datadog_lockfile

    output, status = Open3.capture2e(
      { 'DD_TRACE_SKIP_LIB_INJECTION' => 'true', 'BUNDLE_GEMFILE' => datadog_gemfile.to_s },
      bundle_add_datadog_cmd
    )

    if status.success?
      $stdout.puts '[datadog] Successfully injected datadog into the application.'

      FileUtils.cp datadog_gemfile, gemfile
      FileUtils.cp datadog_lockfile, lockfile
    else
      warn "[datadog] Injection failed: Unable to add datadog. Error output:\n#{output.split("\n").map do |l|
        "[datadog] #{l}"
      end.join("\n")}\n#{support_message}"
    end
  ensure
    # Remove the copies
    FileUtils.rm datadog_gemfile
    FileUtils.rm datadog_lockfile
  end
rescue Exception => e
  warn "[datadog] Injection failed: #{e.class.name} #{e.message}\nBacktrace: #{e.backtrace.join("\n")}\n#{support_message}"
end
