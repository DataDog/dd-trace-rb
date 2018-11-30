module Datadog
  module Shim
    def self.wrap_method_once(object, method_name, &block)
      return if object.nil?

      object.tap do
        object.extend(self)
        object.wrap_method_once(method_name, &block)
      end
    end

    def wrapped_methods
      @wrapped_methods ||= Set.new
    end

    def wrap_method_once(method_name, &block)
      tap do
        unless wrapped_methods.include?(method_name)
          wrap_method(method_name, &block)
          wrapped_methods.add(method_name)
        end
      end
    end

    def wrap_method(method_name, &block)
      tap do
        wrapper = MethodWrapper.new(method(method_name), &block)
        define_singleton_method(method_name, &wrapper.method(:invoke))
      end
    end

    class Double
      extend Forwardable
      include Shim

      EXCLUDED_METHODS = [
        :__id__,
        :__send__,
        :__binding__,
        :itself,
        :object_id,
        :tap,
        # :class,
        :singleton_class,
        :wrap_method,
        :wrap_method_once,
        :wrapped_methods,
        :shim,
        #
        # :try,
        # :try!,
        # :unloadable,
        # :require_or_load,
        # :require_dependency,
        # :load_dependency,

        
        # :public_send,
        # :instance_variables,
        # :instance_variable_set,
        # :instance_variable_defined?,
        # :remove_instance_variable,
        # :private_methods,
        # :kind_of?,
        # :is_a?,
        # :instance_variable_get,
        # :public_method,
        # :singleton_method,
        # :instance_of?,
        # :class_eval,
        # :extend,
        # :define_singleton_method,
        # :method,
        # :to_enum,
        # :enum_for,
        # :pretty_inspect,
        # :<=>,
        # :===,
        # :=~,
        # :!~,
        # :eql?,
        # :respond_to?,
        # :freeze,
        # :inspect,
        # :display,
        # :object_id,
        # :send,
        # :to_s,
        # :gem,
        # :nil?,
        # :hash,
        # :clone,
        # :dup,
        # :itself,
        # :taint,
        # :tainted?,
        # :untaint,
        # :untrust,
        # :trust,
        # :untrusted?,
        # :methods,
        # :protected_methods,
        # :frozen?,
        # :public_methods,
        # :singleton_methods,
        # :!,
        # :==,
        # :!=,
        # :__send__,
        # :equal?,
        # :instance_eval,
        # :instance_exec
      ].freeze

      # EXCLUDED_METHODS = [
      # # :wrap_method,
      # # :wrap_method_once,
      # # :wrapped_methods,
      # # :finish,
      # # :start,
      # # :id,
      # # :instrument,
      # # :finish_with_state,
      # # :to_json,
      # # :to_yaml,
      # # :to_yaml_properties,
      # # :pry,
      # # :present?,
      # :__binding__,
      # # :dclone,
      # # :psych_to_yaml,
      # # :to_query,
      # # :as_json,
      # # :presence,
      # # :blank?,
      # # :deep_dup,
      # # :duplicable?,
      # # :acts_like?,
      # # :to_param,
      # # :instance_values,
      # # :instance_variable_names,
      # :try,
      # :try!,
      # :unloadable,
      # :require_or_load,
      # :require_dependency,
      # :load_dependency,

      # :tap,
      # :public_send,
      # :instance_variables,
      # :instance_variable_set,
      # :instance_variable_defined?,
      # :remove_instance_variable,
      # :private_methods,
      # :kind_of?,
      # :is_a?,
      # :instance_variable_get,
      # :public_method,
      # :singleton_method,
      # :instance_of?,
      # :class_eval,
      # :extend,
      # :define_singleton_method,
      # :method,
      # :to_enum,
      # :enum_for,
      # :pretty_inspect,
      # :<=>,
      # :===,
      # :=~,
      # :!~,
      # :eql?,
      # :respond_to?,
      # :freeze,
      # :inspect,
      # :display,
      # :object_id,
      # :send,
      # :to_s,
      # :gem,
      # :nil?,
      # :hash,

      # :class,
      # :singleton_class,
      # :clone,
      # :dup,
      # :itself,
      # :taint,
      # :tainted?,
      # :untaint,
      # :untrust,
      # :trust,
      # :untrusted?,
      # :methods,
      # :protected_methods,
      # :frozen?,
      # :public_methods,
      # :singleton_methods,
      # :!,
      # :==,
      # :!=,
      # :__send__,
      # :equal?,
      # :instance_eval,
      # :instance_exec,
      # :__id__].freeze

      # EXCLUDED_METHODS = Class.new.methods.freeze

      def initialize(target, *forwarded_methods, &block)
        @target = target

        instance_eval(&block)

        # Forward methods
        forwarded_methods = target.public_methods if forwarded_methods.empty?
        singleton_class.send(
          :def_delegators,
          :@target,
          *(forwarded_methods - EXCLUDED_METHODS)
        )
      end

      def wrapped_methods
        @wrapped_methods ||= Set.new
      end

      def wrap_method_once(method_name, &block)
        tap do
          unless wrapped_methods.include?(method_name)
            wrap_method(method_name, &block)
            wrapped_methods.add(method_name)
          end
        end
      end

      def wrap_method(method_name, &block)
        tap do
          wrapper = MethodWrapper.new(@target.method(method_name), &block)
          define_singleton_method(method_name, &wrapper.method(:invoke))
        end
      end

      def shim
        self
      end
    end

    class MethodWrapper
      attr_reader \
        :original,
        :wrapper

      DEFAULT_WRAPPER = Proc.new { |*args, &block| original.call(*args, &block) }

      def initialize(original, &block)
        @original = original
        @wrapper = block_given? ? block : DEFAULT_WRAPPER
      end

      def invoke(*args, &block)
        wrapper.call(original, *args, &block)
      end
    end
  end
end
