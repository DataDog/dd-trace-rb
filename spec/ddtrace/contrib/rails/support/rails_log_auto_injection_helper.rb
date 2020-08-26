require 'json'

module RailsLogAutoInjectionHelper
  def read_logs
    File.read('./spec/ddtrace/contrib/rails/support/test_logs.log')
  end

  def wipe_logs
    File.open('./spec/ddtrace/contrib/rails/support/test_logs.log', 'w') { |file| file.truncate(0) }
  end

  module_function :read_logs, :wipe_logs
end
