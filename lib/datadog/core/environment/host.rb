# typed: false

require 'datadog/core/environment/identity'

module Datadog
  module Core
    module Environment
      # For gathering os information
      module Host
        module_function

        def hostname
          Identity.lang_version >= '2.2' ? Etc.uname[:nodename] : nil
        end

        def kernel_name
          Identity.lang_version >= '2.2' ? Etc.uname[:sysname] : Gem::Platform.local.os.capitalize
        end

        def kernel_release
          if Identity.lang_engine == 'jruby'
            Etc.uname[:version]  # Java's `os.version` maps to `uname -r`
          elsif Identity.lang_version >= '2.2'
            Etc.uname[:release]
          end
        end

        def kernel_version
          Etc.uname[:version] if Identity.lang_engine != 'jruby' && Identity.lang_version >= '2.2'
        end
      end
    end
  end
end
