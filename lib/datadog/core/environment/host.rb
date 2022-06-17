# typed: false

require 'datadog/core/environment/ext'

module Datadog
  module Core
    module Environment
      # For gathering os information
      module Host
        module_function

        def hostname
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:nodename] : nil
        end

        def kernel_name
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:sysname] : Gem::Platform.local.os.capitalize
        end

        def kernel_release
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:release] : nil
        end

        def kernel_version
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:version] : nil
        end
      end
    end
  end
end
