module Datadog
  module Quantization
    # Quantization for HTTP resources
    module Hash
      PLACEHOLDER = '?'.freeze
      EXCLUDE_KEYS = [].freeze
      SHOW_KEYS = [].freeze
      DEFAULT_OPTIONS = {
        exclude: EXCLUDE_KEYS,
        show: SHOW_KEYS,
        placeholder: PLACEHOLDER
      }.freeze

      module_function

      def format(hash_obj, options = {})
        format!(hash_obj, options)
      rescue StandardError
        options[:placeholder] || PLACEHOLDER
      end

      def format!(hash_obj, options = {})
        options = merge_options(DEFAULT_OPTIONS, options)
        format_hash(hash_obj, options)
      end

      def format_hash(hash_obj, options = {})
        return hash_obj if options[:show] == :all

        case hash_obj
        when ::Hash
          hash_obj.each_with_object({}) do |(key, value), quantized|
            if options[:show].include?(key.to_sym)
              quantized[key] = value
            elsif !options[:exclude].include?(key.to_sym)
              quantized[key] = format_value(value, options)
            end
          end
        else
          format_value(hash_obj, options)
        end
      end

      def format_value(value, options = {})
        return value if options[:show] == :all

        case value
        when ::Hash
          format_hash(value, options)
        when Array
          # If any are objects, format them.
          if value.any? { |v| v.class <= ::Hash || v.class <= Array }
            value.collect { |i| format_value(i, options) }
          # Otherwise short-circuit and return single placeholder
          else
            options[:placeholder]
          end
        else
          options[:placeholder]
        end
      end

      def merge_options(original, additional)
        {}.tap do |options|
          # Show
          # If either is :all, value becomes :all
          options[:show] = if original[:show] == :all || additional[:show] == :all
                             :all
                           else
                             (original[:show] || []).dup.concat(additional[:show] || []).uniq
                           end

          # Exclude
          options[:exclude] = (original[:exclude] || []).dup.concat(additional[:exclude] || []).uniq
          options[:placeholder] = additional[:placeholder] || original[:placeholder]
        end
      end
    end
  end
end
