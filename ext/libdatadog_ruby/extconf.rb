# rubocop:disable Style/StderrPuts
# rubocop:disable Style/GlobalVars

require 'mkmf'
require 'libdatadog'

# If we got here, libdatadog is available and loaded
ENV['PKG_CONFIG_PATH'] = "#{ENV['PKG_CONFIG_PATH']}:#{Libdatadog.pkgconfig_folder}"
Logging.message("[datadog] PKG_CONFIG_PATH set to #{ENV['PKG_CONFIG_PATH'].inspect}\n")
$stderr.puts("Using libdatadog #{Libdatadog::VERSION} from #{Libdatadog.pkgconfig_folder}")

unless pkg_config('datadog_profiling_with_rpath')
  Logging.message("[datadog] Ruby detected the pkg-config command is #{$PKGCONFIG.inspect}\n")
end

create_makefile("libdatadog_ruby")

