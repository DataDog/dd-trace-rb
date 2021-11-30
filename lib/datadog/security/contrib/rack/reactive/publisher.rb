require 'datadog/security/contrib/rack/request'

module Datadog
  module Security
    module Contrib
      module Rack
        module Reactive
          module Publisher
            def self.publish(op, request)
              catch(:block) do
                op.publish('request.query', Request.query(request))
                op.publish('request.headers', Request.headers(request))
                op.publish('request.uri.raw', request.url)
                op.publish('request.cookies', request.cookies)
                op.publish('request.body.raw', Request.body(request))
                # TODO: op.publish('request.path_params', { k: v }) # route params only?
                # TODO: op.publish('request.path', request.script_name + request.path) # unused for now

                nil
              end
            end
          end
        end
      end
    end
  end
end
