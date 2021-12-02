def init
  super
  sections.push :public_api
end

def public_api
  return unless object.has_tag?(:public_api)
  erb(:public_api)
end
