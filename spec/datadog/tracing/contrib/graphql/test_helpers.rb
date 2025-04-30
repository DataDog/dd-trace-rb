module Datadog
  module GraphQLTestHelpers
    module_function

    # Workaround to reset internal state
    def reset_schema_cache!(s)
      [
        '@own_tracers',
        '@trace_modes',
        '@trace_class',
        '@tracers',
        '@graphql_definition',
        '@own_trace_modes',
      ].each do |i_var|
        s.remove_instance_variable(i_var) if s.instance_variable_defined?(i_var)
      end
    end
  end
end
