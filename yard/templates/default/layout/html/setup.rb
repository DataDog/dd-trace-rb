def menu_lists
  # Prepend Public API to existing menus
  [ { :type => 'public_api', :title => 'Public API', :search_title => 'Public API' } ] + super
end

def stylesheets
  # Append custom Datadog stylesheet
  super + %w(css/datadog.css)
end
