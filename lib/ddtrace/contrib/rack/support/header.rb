# frozen_string_literal: true

module Datadog
  module Contrib
    module Rack
      module Support
        # Rack integration constants TODO
        module Header
          module_function

          def to_rack(name)
            header = name.to_s.upcase
            header.gsub!(/-/o, '_') # TODO: look up /o

            "HTTP_#{header}"
          end
        end
      end
    end
  end
end
