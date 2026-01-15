#!/usr/bin/env ruby

require "steep"
require "parser/ruby25"
require "json"

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

def ast_traversal(declarations, result = {})
  result[:methods] ||= []
  result[:others] ||= []
  declarations.each do |declaration|
    case declaration
    when ::RBS::AST::Declarations::Module,
         ::RBS::AST::Declarations::Class,
         ::RBS::AST::Declarations::Interface
      ast_traversal(declaration.members, result)
    when ::RBS::AST::Declarations::TypeAlias,
      ::RBS::AST::Declarations::Constant,
      ::RBS::AST::Declarations::Global,
      ::RBS::AST::Members::Var,
      ::RBS::AST::Members::Attribute
      result[:others] << declaration
    # Only this one does not have a type field
    when ::RBS::AST::Members::MethodDefinition
      result[:methods] << declaration
    end
  end
  result
end

def combine_two_type_results(r1, r2)
  return r2 if r1.nil?
  return r1 if r2.nil?
  return :typed if r1 == :typed && r2 == :typed
  return :untyped if r1 == :untyped && r2 == :untyped
  :partial
end

def combine_multiple_type_results(*results)
  results.inject(nil) do |acc, result|
    result = combine_two_type_results(acc, result)
    return :partial if result == :partial
    result
  end
end

def compute_multiple_types(types, initialize: false)
  types.inject(nil) do |acc, type|
    result = combine_two_type_results(acc, is_typed?(type, initialize: initialize))
    return :partial if result == :partial
    result
  end
end

# Returns :typed, :untyped, :partial or nil (neutral state)
def is_typed?(type, initialize: false)
  return nil if type.nil?

  case type
  when ::RBS::Types::Bases::Any
    return :untyped
  # If function is initialize, void return type should not impact the typing.
  when ::RBS::Types::Bases::Void
    return initialize ? nil : :typed
  when ::RBS::Types::Bases::Base,
       ::RBS::Types::Literal,
       ::RBS::Types::Variable,
       ::RBS::Types::Alias,
       ::RBS::Types::ClassSingleton
    return :typed
  when ::RBS::Types::Record
    return compute_multiple_types(type.all_fields.values.map(&:first))
  when ::RBS::Types::Optional,
       ::RBS::Types::Function::Param
    return is_typed?(type.type)
  when ::RBS::Types::Proc,
       ::RBS::Types::Block
    result = combine_two_type_results(is_typed?(type.self_type), is_typed?(type.type))
    if type.is_a?(::RBS::Types::Proc)
      result = combine_two_type_results(result, is_typed?(type.block))
    end
    return result
  when ::RBS::Types::UntypedFunction
    return is_typed?(type.return_type)
  when ::RBS::Types::Function
    # each param array is an array of Param, except for rest_positionals and rest_keywords
    return combine_multiple_type_results(
      compute_multiple_types(type.required_positionals),
      compute_multiple_types(type.optional_positionals),
      is_typed?(type.rest_positionals),
      compute_multiple_types(type.trailing_positionals),
      compute_multiple_types(type.required_keywords.values),
      compute_multiple_types(type.optional_keywords.values),
      is_typed?(type.rest_keywords),
      # We set initialize to true in the caller method if the method is initialize
      is_typed?(type.return_type, initialize: initialize)
    )
  when ::RBS::Types::Intersection,
       ::RBS::Types::Union,
       ::RBS::Types::Tuple
    return compute_multiple_types(type.types)
  # A class instance or an interface is already a type. However the args can be untyped.
  # E.g. Array[untyped]. This should be considered partially typed.
  when ::RBS::Types::ClassInstance,
       ::RBS::Types::Interface
    args_result = compute_multiple_types(type.args)
    return :partial if args_result == :partial || args_result == :untyped
    :typed
  # Used as the starting point:
  when ::RBS::MethodType
    return combine_two_type_results(is_typed?(type.type, initialize: initialize), is_typed?(type.block))
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
  buffer = ::RBS::Buffer.new(name: sig_path, content: sig_file_content)
  _, _directives, declarations = ::RBS::Parser.parse_signature(buffer)
  filtered_declarations = ast_traversal(declarations)

  filtered_declarations[:methods].each do |method|
    # Overloading can be done inline so we cannot point to the specific overloaded method definition.
    # That's why we combine the status of all overloads to get the overall status of the method.
    # method.overload is an array of MethodDefinition::Overload
    initialize = method.kind == :instance && method.name == :initialize
    result = compute_multiple_types(method.overloads.map { |overload| overload.method_type }, initialize: initialize)
    case result
    when :typed
      typed_methods_size += 1
    when :untyped
      untyped_methods << {path: sig_path.to_s, line: method.location.start_line, line_content: method.location.source}
    when :partial
      partially_typed_methods << {path: sig_path.to_s, line: method.location.start_line, line_content: method.location.source}
    end
  end

  filtered_declarations[:others].each do |declaration|
    result = is_typed?(declaration.type)
    case result
    when :typed, nil
      typed_others_size += 1
    when :untyped
      untyped_others << {path: sig_path.to_s, line: declaration.location.start_line, line_content: declaration.location.source}
    when :partial
      partially_typed_others << {path: sig_path.to_s, line: declaration.location.start_line, line_content: declaration.location.source}
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
