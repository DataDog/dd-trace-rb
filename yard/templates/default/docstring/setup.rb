# frozen_string_literal: true

# def init
#   return if object.docstring.blank? && !object.has_tag?(:api)
#   sections :index, [:private, :deprecated, :abstract, :todo, :note, :returns_void, :text], T('tags')
# end

def deprecated
  return unless object.has_tag?(:deprecated)

  erb(:deprecated)
end
