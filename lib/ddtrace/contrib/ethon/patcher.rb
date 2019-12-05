module Datadog
  module Contrib
    module Ethon
      # Patcher enables patching of 'ethon' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/ext/app_types'
          require 'ddtrace/contrib/ethon/easy_patch'
          require 'ddtrace/contrib/ethon/multi_patch'

          ::Ethon::Easy.send(:include, EasyPatch)
          ::Ethon::Multi.send(:include, MultiPatch)
        end
      end
    end
  end
end
