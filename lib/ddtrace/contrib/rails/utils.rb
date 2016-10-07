module Datadog
  module Utils
    # in Rails the template name includes the full folder path
    # and it's better to avoid storing such information
    def self.normalize_template_name(name)
      return if name.nil?
      name.split('/')[-1]
    end
  end
end
