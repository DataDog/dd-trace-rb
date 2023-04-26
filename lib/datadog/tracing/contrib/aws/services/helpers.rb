# frozen_string_literal: true

require_relative 'sqs'
require_relative 'sns'
require_relative 'dynamodb'
require_relative 'kinesis'
require_relative 'eventbridge'
require_relative 'stepfunctions'
require_relative 's3'

def add_service_specific_tags(span, aws_service, params)
  case aws_service
  when 'sqs'
    add_sqs_tags(span, params)
  when 'sns'
    add_sns_tags(span, params)
  when 'dynamodb'
    add_dynamodb_tags(span, params)
  when 'kinesis'
    add_kinesis_tags(span, params)
  when 'eventbridge'
    add_eventbridge_tags(span, params)
  when 'states'
    add_states_tags(span, params)
  when 's3'
    add_s3_tags(span, params)
  end
end
