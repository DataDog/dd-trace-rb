module Acme
  module Views
    module Books
      class Index
        include Acme::View

        def bookshelf
          "Doghouse"
        end
      end
    end
  end
end
