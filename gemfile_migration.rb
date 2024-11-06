#!/usr/bin/env ruby

require 'fileutils'

[
  "2.5",
  "2.6",
  "2.7",
  "3.0",
  "3.1",
  "3.2",
  "3.3",
  "3.4",
  "jruby-9.2",
  "jruby-9.3",
  "jruby-9.4",
].each do |v|
  # For example:
  # - Gemfile-3.3 -> ruby-3.3.gemfile
  # - Gemfile-jruby-9.3 -> jruby-9.3.gemfile
  original_file_name = "Gemfile-#{v}"
  target = v.start_with?("jruby") ? v : "ruby-#{v}"
  new_file_name = "#{target}.gemfile"

  # Migrate symlinked versioned Gemfile to a new file without symlinked
  FileUtils.rm(original_file_name)
  FileUtils.cp("Gemfile", new_file_name)

  # Update docker-compose.yml
  text = File.read("docker-compose.yml")
  new_contents = text.gsub(original_file_name, new_file_name)
  File.open("docker-compose.yml", "w") {|file| file.puts new_contents }
end

eval_gemfile = 'eval_gemfile("#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION.split(".").take(2).join(".")}.gemfile")'
File.open("Gemfile", "w") {|file| file.puts(eval_gemfile)}
