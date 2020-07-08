module LanguageHelpers
  module HashHelpers
    # Introduced in Ruby 2.5
    def transform_keys
      result = self.class.new
      each_key do |key|
        result[yield(key)] = self[key]
      end
      result
    end

    def stringify_keys
      transform_keys(&:to_s)
    end

    def symbolize_keys
      transform_keys(&:to_sym)
    end
  end
end

# Prepend was private in Ruby 2.0
Hash.send(:prepend, LanguageHelpers::HashHelpers)
