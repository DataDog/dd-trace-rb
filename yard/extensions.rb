# frozen_string_literal: true

TOP_LEVEL_MODULE_FILE = 'lib/ddtrace.rb'

# The top-level `Datadog` module gets its docstring overwritten by
# on almost every file in the repo, due to comments at the top of the file
# (e.g. '# typed: true' or from vendor files 'Copyright (c) 2001-2010 Not Datadog.')
#
# This module ensures that only the comment provided by 'lib/ddtrace.rb'
# is used as documentation for the top-level `Datadog` module.
#
# For non-top-level documentation, this can be solved by removing duplicate module/class
# documentation. But for top-level it's tricky, as it is common to leave general comments
# and directives in the first lines of a file.
module EnsureTopLevelModuleCommentConsistency
  def register_docstring(object, *args)
    if object.is_a?(YARD::CodeObjects::ModuleObject) && object.path == 'Datadog' && parser.file != TOP_LEVEL_MODULE_FILE
      super(object, nil)
    else
      super
    end
  end
end
YARD::Handlers::Base.prepend(EnsureTopLevelModuleCommentConsistency)

# Sanity check to ensure we haven't renamed the top-level module definition file.
YARD::Parser::SourceParser.before_parse_list do |files, _global_state|
  raise "Top-level module file not found: #{TOP_LEVEL_MODULE_FILE}. Has it been moved?" unless
    files.include?(TOP_LEVEL_MODULE_FILE)
end

# Hides all objects that are not part of the Public API from YARD docs.
YARD::Parser::SourceParser.after_parse_list do
  YARD::Registry.each do |obj|
    obj.visibility = :private unless obj.has_tag?('public_api')
  end
end

# Remove magic comments from documentation (e.g. Rubocop directives, TODOs, DEVs)
YARD::Parser::SourceParser.after_parse_list do
  YARD::Registry.each do |obj|
    docstring = obj.docstring
    next if docstring.empty?

    docstring.replace(docstring.all.gsub(/^[A-Z]+: .*/, '')) # Removes TODO:, DEV:
    docstring.replace(docstring.all.gsub(/^rubocop:.*/, '')) # Removes rubocop:...
  end
end

#
# Generates modules for DSL categories created by {Datadog::Configuration::Base::ClassMethods#settings}.
# `#settings` are groups that can contain multiple `#option`s or nested `#settings.`
#
class DatadogConfigurationSettingsHandler < YARD::Handlers::Ruby::Base
  handles method_call(:settings)

  process do
    next if statement.is_a?(YARD::Parser::Ruby::ReferenceNode)

    name = call_params[0]

    if namespace.has_tag?(:dsl) # Check if we are already nested inside the DSL namespace
      parent_module = namespace
    else
      # If not, create a DSL module to host generated classes
      parent_module = YARD::CodeObjects::ModuleObject.new(namespace, 'DSL') do |o|
        o.docstring = 'Namespace for dynamically generated configuration classes.'
      end

      register(parent_module)
    end

    generated_class = YARD::CodeObjects::ClassObject.new(parent_module, camelize(name)) do |o|
      o.docstring = 'Namespace for dynamically generated configuration classes.'
      o.add_tag(YARD::Tags::Tag.new(:dsl, 'dsl'))
    end

    register(generated_class)

    statement.docstring = <<~YARD
      #{statement.docstring}
      @return [#{generated_class.path}] a configuration object
    YARD

    statement.block.last.each do |node|
      parse_block(node, :namespace => generated_class)
    end
  end
end

#
# Generates attributes for DSL options created by {Datadog::Configuration::Options::ClassMethods#option}.
# `#option`s are read/write configurable attributes.
#
class DatadogConfigurationOptionHandler < YARD::Handlers::Ruby::Base
  handles method_call(:option)

  process do
    next if statement.is_a?(YARD::Parser::Ruby::ReferenceNode)

    # Convert this method call into a read/write attribute.
    # The easiest way to do this is by invoking YARD's AttributeHandler.
    # We trick AttributeHandler into thinking this is an `attr_accessor`
    # node, instead of a method call node.
    attr_statement = statement.dup
    attr_statement.define_singleton_method(:method_name) { |*_args| :attr_accessor }

    # Remove additional arguments to `option :name`, like `default:`.
    # These won't parse correctly when we parse
    # `option :name, default: 1` as `attr_accessor :name, default: 1`.
    statement[1].slice!(1..-2)

    attr = YARD::Handlers::Ruby::AttributeHandler.new(parser, attr_statement)
    attr.process
  end
end

def camelize(str)
  str.split('_').collect(&:capitalize).join
end
