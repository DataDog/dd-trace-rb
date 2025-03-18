#!/usr/bin/env ruby

require 'json'

begin
  # Check if an argument was provided
  if ARGV.empty?
    puts 'Error: No JSON input provided. Please provide needs JSON as first argument.'
    exit 1
  end

  # Parse from command line argument
  jobs = JSON.parse(ARGV[0])

  puts jobs

  all_success = true

  jobs.each do |name, data|
    if data['result'] != 'success'
      puts "Job #{name} failed or was skipped (status: #{data['result']})"
      all_success = false
    end
  end

  if all_success
    puts 'All needed jobs completed successfully'
    exit 0
  else
    puts 'Some required jobs did not complete successfully'
    exit 1
  end
rescue JSON::ParserError => e
  puts "Error parsing needs JSON: #{e.message}"
  exit 1
end
