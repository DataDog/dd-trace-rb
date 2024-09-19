module Acme
  module Controllers
    module Books
      class Show
        include Acme::Action

        def call(params)
=begin Uncomment for testing failures
          # binding.pry
          if rand > 0.5
            raise "Oooops...."
          end
=end
        end
      end
    end
  end
end
