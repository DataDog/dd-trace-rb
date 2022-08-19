# typed: true

require_relative './tracer'

module Datadog
  module Tracing
    # A class may include {Datadog::Tracing::Traceable} to bring in some handy helpers to aid in creating
    # traces around its own methods, or use values from its methods as tags on the current span.
    module Traceable
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Wrap `method` in a {Datadog::Tracing#trace} block, with an operation name. Any extra kwargs will be
        # passed to {Datadog::Tracing::Tracer#trace}.
        #
        # ```
        # class MyClass
        #   include Datadog::Tracing::Traceable
        #
        #   datadog_trace_method :load_data, operation_name: "my_class.load_data", tags: { my_tag: "value" }
        #
        #   def load_data
        #     File.read("")
        #   end
        # end
        # ```
        #
        # @param method [Symbol, String, Method] the method that should be wrapped in a {Datadog::Tracing#trace} block
        # @param operation_name [String] the name of the operation for the new span (the first argument to {Datadog::Tracing#trace})
        # @public_api
        def datadog_trace_method(method, operation_name:, **trace_options)
          method = method.name if method.is_a? Method
          unless method_defined?(method) || private_method_defined?(method)
            raise ArgumentError, "Could not find method '#{method}' on #{self.inspect} to trace"
          end

          return unless Tracing.enabled?

          mod = module_to_prepend method, :datadog_trace_method do
            define_method method do |*args, &block|
              Tracing.trace operation_name, **trace_options do
                super(*args, &block)
              end
            end
          end

          mod.send(method_scope(method), method)
          prepend(mod)
        end

        # Intercept calls to the named `method` and use its return value as the value of a tag on the span active
        # when the method is called. The tag name is the method name, but can be overridden using the `tag` param.
        # The tag is added lazily, the tag will not be added if the method is not called by other code in your app.
        #
        # To add a span tag based on the value of the method, include the module and call `datadog_span_tag_from`:
        # ```
        # class MyClass
        #   include Datadog::Tracing::Traceable
        #
        #   datadog_span_tag :name
        #
        #   private
        #
        #   def name
        #     "this will be the tag value"
        #   end
        # end
        # ```
        #
        # To add a tag with a custom tag name:
        # ```
        # class AdminController
        #   include Datadog::Tracing::Traceable
        #
        #   datadog_span_tag :user_name, tag: "user.name"
        #
        #   private
        #
        #   def user_name
        #     current_admin_user.name
        #   end
        # end
        # ```
        #
        # To add a tag extracted from a complex object returned by a method:
        # ```
        # class UsersController
        #   include Datadog::Tracing::Traceable
        #
        #   datadog_span_tag :current_user, tag: "user.id" { |user| user.id }
        #
        #   private
        #
        #   def current_user
        #     User.find(session[:user_id])
        #   end
        # end
        # ```
        #
        # @param method [Symbol, String, Method] the method whose value should be used for the new span tag
        # @param tag_name [String] the name of the tag to set on the active span
        # @yield optional block that receives the value returned from the method, whose return value will be used as the
        #        value of the tag
        # @yieldparam [Object] the value returned from the method
        # @public_api
        def datadog_span_tag(method, tag: nil, &block)
          method = method.name if method.is_a? Method
          unless method_defined?(method) || private_method_defined?(method)
            raise ArgumentError, "Could not find method '#{method}' on #{self.inspect} to add as a span tag"
          end

          return unless Tracing.enabled?

          tag = method.to_s unless tag

          mod = module_to_prepend(method, :datadog_span_tag) do
            define_method method do |*args, &method_block|
              super(*args, &block).tap do |value|
                value = block.call(value) unless block.nil?
                Tracing.active_span&.set_tag(tag, value)
              end
            end
          end

          mod.send(method_scope(method), method)
          prepend(mod)
        end

        private

        def method_scope(method)
          if private_method_defined?(method)
            :private
          elsif protected_method_defined?(method)
            :protected
          else
            :public
          end
        end

        def module_to_prepend(method, traceable, &block)
          Module.new do
            define_singleton_method(:inspect) do
              "Datadog::Tracing::Traceable (for method=#{method.inspect} traceable=#{traceable.inspect})"
            end

            module_eval &block
          end
        end
      end
    end
  end
end
