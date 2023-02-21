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

    # Copies for trial
    system "cp Gemfile Gemfile-datadog"
    system "cp Gemfile.lock Gemfile-datadog.lock"

    if system "skip_autoinject=true BUNDLE_GEMFILE=Gemfile-datadog bundle add ddtrace #{condition} --require ddtrace/auto_instrument"
      puts 'ddtrace added to bundle...'

      # Trial success, replace the original
      system "cp Gemfile-datadog Gemfile"
      system "cp Gemfile-datadog.lock Gemfile.lock"
    else
      puts 'Something went wrong when adding ddtrace to bundle...'
    end

    # Remove the copies
    system "rm Gemfile-datadog Gemfile-datadog.lock"
  end

  begin
    require 'ddtrace'
  rescue LoadError => e
    puts e
  else
    puts 'ddtrace loaded...'
  end
end
