
if !ENV['skip_autoinject']
  if system 'skip_autoinject=true bundle show ddtrace'
    puts 'ddtrace already installed... skipping auto-injection'
  else
    version = "<DD_TRACE_VERSION_TO_BE_REPLACED>"
    puts "ddtrace is not installed... Perform auto-injection... for dd-trace-rb:#{version}"

    if system "skip_autoinject=true bundle add ddtrace --version #{version} --require ddtrace/auto_instrument"
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
