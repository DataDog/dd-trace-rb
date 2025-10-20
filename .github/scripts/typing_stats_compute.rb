#!/usr/bin/env ruby

require "steep"
require "parser/ruby25"
require "json"

METHOD_AND_PARAM_NAME = /(?:\w*|`[^`]+`)/
PARAMETER = /(?:\*{1,2})?\s*(?:\??\s*untyped\s*\??\s*|\??#{METHOD_AND_PARAM_NAME}:\s*untyped\s*\??)\s*#{METHOD_AND_PARAM_NAME}/
PARAMETERS = /\(\s*(?:\?|(?:(?:#{PARAMETER})\s*(?:,\s*(?:#{PARAMETER})\s*)*)?)\s*\)/
PROTOTYPE_INITIALIZE = /\s*(?:public|private)?\s*def\s+initialize:\s*#{PARAMETERS}(?:\s*\??\{\s*#{PARAMETERS}\s*->\s*untyped\s*\})?\s*->\s*void/
PROTOTYPE_METHOD = /\s*(?:public|private)?\s*def\s+(?:self\??\.)?(?:[^\s]+):\s*#{PARAMETERS}(?:\s*\??\{\s*#{PARAMETERS}\s*->\s*untyped\s*\})?\s*->\s*untyped/

steepfile_path = Pathname(ENV["STEEPFILE_PATH"])
project = Steep::Project.new(steepfile_path: steepfile_path).tap do |project|
  Steep::Project::DSL.parse(project, steepfile_path.read, filename: steepfile_path.to_s)
end
datadog_target = project.targets&.find { |target| target.name == :datadog }
loader = ::Steep::Services::FileLoader.new(base_dir: project.base_dir)

ignored_paths_with_folders = datadog_target&.source_pattern&.ignores

ignored_files = ignored_paths_with_folders.each_with_object([]) do |ignored_path, result|
  # If the ignored path is a folder, add all the .rb files in the folder to the ignored paths
  if ignored_path.end_with?("/")
    result.push(*Dir.glob(ignored_path + "**/*.rb"))
  else
    result.push(ignored_path)
  end
end

# List signature files that are not related to ignored files
signature_paths_with_ignored_files = loader.each_path_in_patterns(datadog_target.signature_pattern)
signature_paths = signature_paths_with_ignored_files.reject do |sig_path|
  corresponding_lib_file = sig_path.to_s.sub(/^sig/, "lib").sub(/\.rbs$/, ".rb")
  ignored_paths_with_folders.any? do |ignored|
    if ignored.end_with?("/")
      # Directory ignore - check if signature file is inside this directory
      corresponding_lib_file.start_with?(ignored)
    else
      # File ignore - check if signature file matches exactly
      corresponding_lib_file == ignored
    end
  end
end

total_files_size = Dir.glob("#{project.base_dir}/lib/**/*.rb").size

# steep:ignore comments stats
ignore_comments = loader.each_path_in_patterns(datadog_target.source_pattern).each_with_object([]) do |path, result|
  buffer = ::Parser::Source::Buffer.new(path.to_s, 1, source: path.read)
  _, comments = ::Parser::Ruby25.new.parse_with_comments(buffer)
  rbs_buffer = ::RBS::Buffer.new(name: path, content: path.read)
  comments.each do |comment|
    ignore = ::Steep::AST::Ignore.parse(comment, rbs_buffer)
    next if ignore.nil? || ignore.is_a?(::Steep::AST::Ignore::IgnoreEnd)

    result << {
      path: path.to_s,
      line: ignore.line
    }
  end
end

# sig files stats
untyped_methods = []
partially_typed_methods = []
typed_methods_size = 0

untyped_others = []
partially_typed_others = []
typed_others_size = 0
signature_paths.each do |sig_path|
  sig_file_content = sig_path.read
  # for each line in the file, check if it matches the regex
  sig_file_content.each_line.with_index(1) do |line, index|
    next if line.strip.empty? || line.strip.start_with?("#") || line.strip.end_with?("# untyped:accept")

    case line
    # Methods
    when PROTOTYPE_INITIALIZE
      untyped_methods << {path: sig_path.to_s, line: index, line_content: line.strip}
    when PROTOTYPE_METHOD
      untyped_methods << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*(?:public|private)?\s*def\s.*untyped/ # Any line containing untyped
      partially_typed_methods << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*(?:public|private)?\s*def\s.*/ # Any line containing a method definition not matched by the other regexes
      typed_methods_size += 1
    # Attributes
    when /^\s*(?:public|private)?\s*attr_(?:reader|writer|accessor)\s.*:\s*untyped/
      untyped_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*(?:public|private)?\s*attr_(?:reader|writer|accessor)\s.*untyped/
      partially_typed_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*(?:public|private)?\s*attr_(?:reader|writer|accessor)\s.*/
      typed_others_size += 1
    # Constants
    when /[A-Z]\w*\s*:\s*untyped/ # We don't match beginning of string as constant can have a namespace prefix
      untyped_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /[A-Z]\w*\s*:[^:].*untyped/
      partially_typed_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /[A-Z]\w*\s*:[^:]/
      typed_others_size += 1
    # Globals
    when /^\s*\$[a-zA-Z]\w+\s*:\s*untyped/
      untyped_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*\$[a-zA-Z]\w+\s*:.*untyped/
      partially_typed_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*\$[a-zA-Z]\w+\s*:/
      typed_others_size += 1
    # Class and instance variables
    when /^\s*@?@\w+\s*:\s*untyped/
      untyped_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*@?@\w+\s*:.*untyped/
      partially_typed_others << {path: sig_path.to_s, line: index, line_content: line.strip}
    when /^\s*@?@\w+\s*:/
      typed_others_size += 1
    end
  end
end

resulting_stats = {
  total_files_size: total_files_size,
  ignored_files: ignored_files,

  steep_ignore_comments: ignore_comments,

  untyped_methods: untyped_methods,
  partially_typed_methods: partially_typed_methods,
  typed_methods_size: typed_methods_size, # Location not needed for already typed methods

  untyped_others: untyped_others,
  partially_typed_others: partially_typed_others,
  typed_others_size: typed_others_size # Location not needed for already typed attributes, constants, globals, instance variables
}

puts resulting_stats.to_json
