module RailsActiveRecordHelpers
  def get_adapter_name
    Datadog::Contrib::Rails::Utils.adapter_name
  end

  def get_database_name
    Datadog::Contrib::Rails::Utils.database_name
  end

  def get_adapter_host
    Datadog::Contrib::Rails::Utils.adapter_host
  end

  def get_adapter_port
    Datadog::Contrib::Rails::Utils.adapter_port
  end
end
