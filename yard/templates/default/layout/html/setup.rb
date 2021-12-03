def menu_lists
  # Append Public API to existing menus
  super + [ { :type => 'public_api', :title => 'Public API', :search_title => 'Public API' } ]
end

def stylesheets
  # Append custom Datadog stylesheet
  super + %w(css/datadog.css)
end
