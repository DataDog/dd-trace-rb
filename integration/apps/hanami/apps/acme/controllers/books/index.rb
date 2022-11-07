module Acme
  module Controllers
    module Books
      class Index
        include Acme::Action

        expose :books

        def call(params)
          @books = [
            OpenStruct.new(title: "The 48 Laws of Power", author: "Robert Greene"),
            OpenStruct.new(title: "Atomic Habits", author: "James Clear")
          ]
        end
      end
    end
  end
end
