# frozen_string_literal: true

module CustomCops
  # Enforces the OpenFeature constant-to-file mapping used by conventional Ruby code.
  # Nested implementation classes are offenses because their expected path is below
  # the parent class's path, requiring them to be extracted into their own files.
  class OpenFeatureNamespacePathCop < RuboCop::Cop::Base
    MSG = '`%<constant>s` belongs in `%<expected>s`, not `%<actual>s`.'

    def on_class(node)
      check_definition(node)
    end

    def on_module(node)
      check_definition(node)
    end

    private

    def check_definition(node)
      return if namespace_wrapper?(node)

      constant_name = qualified_constant_name(node)
      return if allowed_constants.include?(constant_name)

      expected_path = expected_path_for(constant_name)
      actual_path = relative_file_path
      return if expected_path == actual_path

      add_offense(
        node.identifier,
        message: format(MSG, constant: constant_name, expected: expected_path, actual: actual_path)
      )
    end

    def namespace_wrapper?(node)
      body = node.body
      return false unless body

      statements = body.begin_type? ? body.children : [body]
      statements.all? { |statement| statement&.type?(:class, :module) }
    end

    def qualified_constant_name(node)
      namespaces = []
      node.each_ancestor(:class, :module).to_a.reverse_each do |ancestor|
        namespaces = merge_namespaces(namespaces, constant_parts(ancestor.identifier))
      end

      identifier = node.identifier
      return constant_parts(identifier).join('::') if identifier.absolute?

      merge_namespaces(namespaces, constant_parts(identifier)).join('::')
    end

    def constant_parts(identifier)
      identifier.const_name.split('::')
    end

    def merge_namespaces(existing, additional)
      overlap = [existing.length, additional.length].min
      overlap -= 1 until overlap.zero? || existing.last(overlap) == additional.first(overlap)

      existing + additional.drop(overlap)
    end

    def expected_path_for(constant_name)
      segments = constant_name.split('::').map { |segment| underscore(segment) }
      File.join('lib', *segments) + '.rb'
    end

    def underscore(constant)
      constant
        .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\\1_\\2')
        .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
        .downcase
    end

    def relative_file_path
      path = processed_source.file_path.tr('\\', '/')
      root = Dir.pwd.tr('\\', '/') + '/'
      path.start_with?(root) ? path.delete_prefix(root) : path
    end

    def allowed_constants
      Array(cop_config['AllowedConstants'])
    end
  end
end
