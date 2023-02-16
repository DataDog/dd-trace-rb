
if !ENV['skip_autoinject']
  if system 'skip_autoinject=true bundle show ddtrace'
    puts 'ddtrace already installed... skipping auto-injection'
  else
    version = "<DD_TRACE_VERSION_TO_BE_REPLACED>"
    sha = "<DD_TRACE_SHA_TO_BE_REPLACED>"

    condition = if !version.empty?
      "--version '#{version}'"
    elsif !sha.empty?
      "--github 'datadog/dd-trace-rb' --ref '#{sha}'"
    else
      puts "NO VERSION"
    end

    puts "ddtrace is not installed... Perform auto-injection... for dd-trace-rb"

    if system "skip_autoinject=true bundle add ddtrace #{condition} --require ddtrace/auto_instrument"
      puts 'ddtrace added to bundle...'
    else
      puts 'Something went wrong when adding ddtrace to bundle...'
    end
  end

  begin
    require 'ddtrace'
  rescue LoadError => e
    puts e
  else
    puts 'ddtrace loaded...'
  end
end
