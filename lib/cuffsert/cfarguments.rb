require 'open-uri'

# TODO:
# - propagate timeout here (from config?)
# - fail on template body > 51200 bytes
# - creation change-set: args[:change_set_type] = 'CREATE'
# - update change-set: args[:change_set_type] = 'UPDATE'

module CuffSert
  TIMEOUT = 5

  def self.as_cloudformation_args(meta)
    args = {
      :stack_name => meta.stackname,
      :capabilities => %[
        CAPABILITY_IAM
        CAPABILITY_NAMED_IAM
      ],
      :timeout_in_minutes => TIMEOUT,
    }

    unless meta.parameters.empty?
      args[:parameters] = meta.parameters.map do |k, v|
        {:parameter_key => k, :parameter_value => v}
      end
    end

    unless meta.tags.empty?
      args[:tags] = meta.tags.map do |k, v|
        {:key => k, :value => v}
      end
    end

    if meta.stack_uri.scheme == 's3'
      args[:template_url] = meta.stack_uri.to_s
    elsif meta.stack_uri.scheme == 'file'
      file = meta.stack_uri.to_s.sub(/^file:\/+/, '/')
      args[:template_body] = open(file).read
    else
      raise "Unsupported scheme #{meta.stack_uri.scheme}"
    end
    args
  end

  def self.as_create_stack_args(meta)
    args = self.as_cloudformation_args(meta)
    args[:on_failure] = 'DELETE'
    args
  end

  def self.as_update_stack_args(meta)
    args = self.as_cloudformation_args(meta)
    args[:use_previous_template] = false
    args
  end

  def self.as_delete_stack_args(meta)
    { :stack_name => meta.stackname }
  end
end
