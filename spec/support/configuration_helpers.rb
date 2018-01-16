module ConfigurationHelpers
  # update Datadog user configuration; you should pass:
  #
  # * +key+: the key that should be updated
  # * +value+: the value of the key
  def update_config(key, value)
    Datadog.configuration[:rails][key] = value
    Datadog::Contrib::Rails::Framework.setup
  end

  # reset default configuration and replace any dummy tracer
  # with the global one
  def reset_config
    Datadog.configure do |c|
      c.use :rails
      c.use :redis
    end

    Datadog::Contrib::Rails::Framework.setup
  end

  def remove_patch!(integration)
    Datadog
      .registry[integration]
      .instance_variable_set('@patched', false)
  end
end
