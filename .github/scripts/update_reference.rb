#!/usr/bin/env ruby

# This script updates the reference in a YAML file.

target = ENV.fetch('TARGET')
puts "Target: #{target}"

ref  = ENV.fetch('REF')
puts "Ref: #{ref}"

pattern_string = ENV.fetch('PATTERN')
clean_pattern = pattern_string.gsub(/^\/|\/$/,'')
pattern = Regexp.new(clean_pattern)
puts "Pattern: #{pattern}"

# Read file, update, write back
content = File.read(target)
updated_content = content.gsub(pattern) { "#{$1}#{ref}#{$3}" }
File.write(target, updated_content)

# Report result
if content != updated_content
  puts "✓ Updated references in #{target}"
else
  puts "No references found in #{target}"
end