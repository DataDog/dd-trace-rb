# frozen_string_literal: true

# does condition require a boolean evaluation result? (e.g. if condition is a
# string, should that evaluate to true, false or be an error)
# instance variable reference - @field or field?
# substring takes arbitrary expressions for second and third arguments?
# cannot include variable values in exception messages?
# Ruby regexp syntax is different from pcre, are all other languages
# the same in regexp syntax?
#
# How is string compared to null for e.g. java?
# (variable resolved but value is null) -> eq null
# is nil undefined?
#
# Does php raise/error for nonexistent array/hash access?
#
# any/all: because nested loops are possible, we'll just traverse up
# the scopes until we find the variable that makes sense.
# Top level we will not set @key/@value for arrays.
#
# Is nil empty?
#
# Is retrieving nonexistent local variables supposed to raise exceptions?
# instance variables?
#
# instanceof: class name must be fully qualified

require_relative 'el/expression'
require_relative 'el/compiler'
require_relative 'el/context'
require_relative 'el/evaluator'
