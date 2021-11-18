#
# Generates modules for DSL categories created by {Datadog::Configuration::Base::ClassMethods#settings}.
# `#settings` are groups that can contain multiple `#option`s or nested `#settings.`
#
class DatadogConfigurationSettingsHandler < YARD::Handlers::Ruby::Base
  handles method_call(:settings)

  process do
    next if statement.is_a?(YARD::Parser::Ruby::ReferenceNode)

    name = call_params[0]

    generated_module = YARD::CodeObjects::ModuleObject.new(namespace, 'Generated') do |o|
      o.docstring = 'Namespace for dynamically generated configuration classes.'
    end

    register(generated_module)

    generated_class = YARD::CodeObjects::ClassObject.new(generated_module, camelize(name)) do |o|
      o.docstring = 'Namespace for dynamically generated configuration classes.'
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
