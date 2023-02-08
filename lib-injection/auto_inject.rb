if ENV['DDTRACE_AUTOINJECT'] && !ENV['skip_autoinject']
  if system 'skip_autoinject=true bundle show ddtrace'
    puts 'ddtrace already installed...'
  else
    puts 'ddtrace is not installed... Perform auto-injection...'

    if system 'skip_autoinject=true bundle add ddtrace --require ddtrace/auto_instrument'
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
