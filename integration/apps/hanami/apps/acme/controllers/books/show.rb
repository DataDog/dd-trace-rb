module Acme
  module Controllers
    module Books
      class Show
        include Acme::Action

        def call(params)
          # binding.pry
          if rand > 0.5
            raise "Oooops...."
          end
        end
      end
    end
  end
end
