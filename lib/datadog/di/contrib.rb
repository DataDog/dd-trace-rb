# frozen_string_literal: true

require_relative '../core/contrib/rails/utils'

module Datadog
  module DI
    module Contrib
      module_function def load_now_or_later
        if Datadog::Core::Contrib::Rails::Utils.railtie_supported?
          require_relative 'contrib/railtie'
        else
          load_now
        end
      end

      module_function def load_now
        if defined?(ActiveRecord::Base)
          require_relative 'contrib/active_record'
        end
      end
    end
  end
end
