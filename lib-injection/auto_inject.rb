
return if ENV['skip_autoinject']

if system 'skip_autoinject=true bundle show ddtrace'
  puts '[DATADOG LIB INJECTION] ddtrace already installed... skipping auto-injection'
  return
end

begin
  require 'bundler'
  require 'shellwords'

  if Bundler.frozen_bundle?
    puts "[DATADOG LIB INJECTION] Cannot inject with frozen Bundler"
    return
  end

  version = "<DD_TRACE_VERSION_TO_BE_REPLACED>"
  sha = "<DD_TRACE_SHA_TO_BE_REPLACED>"

  # Stronger restrict
  condition = if !version.empty?
    # For public release
    "--version #{version.gsub(/^v/, '').shellwords}"
  elsif !sha.empty?
    # For internal testing
    "--github datadog/dd-trace-rb --ref #{sha.shellwords}"
  end

  unless condition
    puts "[DATADOG LIB INJECTION] NO VERSION"
    return
  end

  puts "[DATADOG LIB INJECTION] ddtrace is not installed... Perform lib injection for dd-trace-rb."

  gemfile   = Bundler::SharedHelpers.default_gemfile
  lockfile  = Bundler::SharedHelpers.default_lockfile

  if gemfile.basename.to_s == 'gems.rb'
    datadog_gemfile = gemfile.dirname + "datadog-Gemfile"
    datadog_lockfile = lockfile.dirname + "datadog-Gemfile.lock"
  else
    datadog_gemfile = gemfile.dirname + ("datadog-#{gemfile.basename}")
    datadog_lockfile = lockfile.dirname + ("datadog-#{lockfile.basename}")
  end

  require 'fileutils'

  begin
    # Copies for trial
    FileUtils.cp gemfile, datadog_gemfile
    FileUtils.cp lockfile, datadog_lockfile

    if system "skip_autoinject=true BUNDLE_GEMFILE=#{datadog_gemfile.to_s.shellwords} bundle add ddtrace #{condition} --require ddtrace/auto_instrument"
      puts '[DATADOG LIB INJECTION] ddtrace added to bundle...'

      # Trial success, replace the original
      FileUtils.cp datadog_gemfile, gemfile
      FileUtils.cp datadog_lockfile, lockfile
    else
      puts '[DATADOG LIB INJECTION] Something went wrong when adding ddtrace to bundle...'
    end

  rescue => e
    puts "[DATADOG LIB INJECTION] #{e}"
  ensure
    # Remove the copies
    FileUtils.rm datadog_gemfile
    FileUtils.rm datadog_lockfile
  end
rescue LoadError, Bundler::BundlerError => e
  puts "[DATADOG LIB INJECTION] #{e}"
end
