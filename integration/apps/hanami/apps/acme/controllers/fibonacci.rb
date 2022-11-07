module Acme
  module Controllers
    module Fibonacci
      def self.included(action)
        action.class_eval do
          before :set_fibonacci
          expose :fibonacci
        end
      end

      private

      def set_fibonacci
        @fibonacci = fib(rand(15..25))
      end

      def fib(n)
        n <= 1 ? n : fib(n-1) + fib(n-2)
      end
    end
  end
end
