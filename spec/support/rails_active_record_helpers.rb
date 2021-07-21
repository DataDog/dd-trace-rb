# typed: true
module RailsActiveRecordHelpers
  def get_adapter_name
    Datadog::Contrib::ActiveRecord::Utils.adapter_name
  end

  def get_database_name
    Datadog::Contrib::ActiveRecord::Utils.database_name
  end

  def get_adapter_host
    Datadog::Contrib::ActiveRecord::Utils.adapter_host
  end

  def get_adapter_port
    Datadog::Contrib::ActiveRecord::Utils.adapter_port
  end
end
