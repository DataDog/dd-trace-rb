module Dummy
  module Controllers
    module Books
      class ServerError
        include Dummy::Action

        def call(params)
          raise 'Oops...'
        end
      end
    end
  end
end
