module Dummy
  module Controllers
    module Books
      class Index
        include Dummy::Action

        def call(params)
          # Do something
        end
      end
    end
  end
end
