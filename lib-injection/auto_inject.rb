if !ENV['skip_autoinject']
  if system 'skip_autoinject=true bundle show ddtrace'
    puts 'ddtrace already installed... skipping auto-injection'
  else
    version = "<DD_TRACE_VERSION_TO_BE_REPLACED>"
    sha = "<DD_TRACE_SHA_TO_BE_REPLACED>"

    condition =
      if !version.empty?
        # For public release
        "--version '#{version.gsub(/^v/, '')}'"
      elsif !sha.empty?
        # For internal testing
        "--github 'datadog/dd-trace-rb' --ref '#{sha}'"
      else
        puts "NO VERSION"
      end

    puts "ddtrace is not installed... Perform auto-injection... for dd-trace-rb"

    require 'bundler'
    require 'fileutils'

    gemfile  = Bundler::SharedHelpers.default_gemfile
    lockfile = Bundler::SharedHelpers.default_lockfile

    datadog_gemfile = gemfile.dirname + ("datadog-#{gemfile.basename}")
    datadog_lockfile = lockfile.dirname + ("datadog-#{lockfile.basename}")

    # Copies for trial
    FileUtils.cp gemfile, datadog_gemfile
    FileUtils.cp lockfile, datadog_lockfile

    if system "skip_autoinject=true BUNDLE_GEMFILE=#{datadog_gemfile} bundle add ddtrace #{condition} --require ddtrace/auto_instrument"
      puts 'ddtrace added to bundle...'

      # Trial success, replace the original
      FileUtils.cp datadog_gemfile, gemfile
      FileUtils.cp datadog_lockfile, lockfile
    else
      puts 'Something went wrong when adding ddtrace to bundle...'
    end

    # Remove the copies
    FileUtils.rm datadog_gemfile
    FileUtils.rm datadog_lockfile
  end

  begin
    require 'ddtrace'
  rescue LoadError => e
    puts e
  else
    puts 'ddtrace loaded...'
  end
end
