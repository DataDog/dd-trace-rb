# frozen_string_literal: true

require "etc"

require_relative "identity"

module Datadog
  module Core
    module Environment
      # For gathering information about the platform
      module Platform
        # @return [String] ISA of host; `uname -m`
        def self.architecture
          Etc.uname[:machine]
        end

        # @return [String] name of host; `uname -n`
        def self.hostname
          Etc.uname[:nodename]
        end

        # System name, normally `Linux` or `Darwin` (but 'Mac OS X' on JRuby);
        # @return [String] name of kernel; `uname -s`.
        def self.kernel_name
          Etc.uname[:sysname]
        end

        # @return [String] kernel release; `uname -r`
        def self.kernel_release
          if Identity.lang_engine == "jruby"
            Etc.uname[:version] # Java's `os.version` maps to `uname -r`
          else
            Etc.uname[:release]
          end
        end

        # @return [String] kernel version; `uname -v`
        def self.kernel_version
          Etc.uname[:version] if Identity.lang_engine != "jruby"
        end
      end
    end
  end
end
