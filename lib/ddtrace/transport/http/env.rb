module Datadog
  module Transport
    module HTTP
      # Data structure for an HTTP request
      class Env < Hash
        attr_reader \
          :request

        def initialize(request, options = nil)
          @request = request

          unless options.nil?
            options.each do |name, value|
              self[name] = value
            end
          end
        end

        def verb
          self[:verb]
        end

        def verb=(value)
          self[:verb] = value
        end

        def path
          self[:path]
        end

        def path=(value)
          self[:path] = value
        end

        def body
          self[:body]
        end

        def body=(value)
          self[:body] = value
        end

        def headers
          self[:headers] ||= {}
        end
      end
    end
  end
end
