require 'cuffbase'
require 'open-uri'
require 'yaml'

# TODO:
# - propagate timeout here (from config?)
# - creation change-set: cfargs[:change_set_type] = 'CREATE'

module CuffSert
  TIMEOUT = 10

  def self.as_cloudformation_args(meta)
    cfargs = {
      :stack_name => meta.stackname,
      :capabilities => %w[
        CAPABILITY_IAM
        CAPABILITY_NAMED_IAM
      ],
    }

    unless meta.parameters.empty?
      cfargs[:parameters] = meta.parameters.map do |k, v|
        if v.nil?
          {:parameter_key => k, :use_previous_value => true}
        else
          {:parameter_key => k, :parameter_value => v.to_s}
        end
      end
    end

    unless meta.tags.empty?
      cfargs[:tags] = meta.tags.map do |k, v|
        {:key => k, :value => v.to_s}
      end
    end

    cfargs.merge!(self.template_parameters(meta))
  end

  def self.as_create_stack_args(meta)
    no_value = meta.parameters.select {|_, v| v.nil? }.keys
    raise CuffBase::InvokationError, "Pealse supply value for #{no_value.join(', ')}" unless no_value.empty?

    cfargs = self.as_cloudformation_args(meta)
    cfargs[:timeout_in_minutes] = TIMEOUT
    cfargs[:on_failure] = 'DELETE'
    cfargs
  end

  def self.as_update_change_set(meta)
    cfargs = self.as_cloudformation_args(meta)
    cfargs[:use_previous_template] = false
    cfargs[:change_set_name] = meta.stackname
    cfargs[:change_set_type] = 'UPDATE'
    cfargs
  end

  def self.as_delete_stack_args(stack)
    { :stack_name => stack[:stack_id] }
  end

  def self.s3_uri_to_https(uri)
    region = ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION'] || 'us-east-1'
    bucket = uri.host
    key = uri.path
    host = region == 'us-east-1' ? 's3.amazonaws.com' : "s3-#{region}.amazonaws.com"
    "https://#{host}/#{bucket}#{key}"
  end

  private_class_method

  def self.load_minified_template(file)
    template = open(file).read
    YAML.load(template).to_json
  end

  def self.template_parameters(meta)
    template_parameters = {}

    if meta.stack_uri.scheme == 's3'
      template_parameters[:template_url] = self.s3_uri_to_https(meta.stack_uri)
    elsif meta.stack_uri.scheme == 'https'
      if meta.stack_uri.host.end_with?('amazonaws.com')
        template_parameters[:template_url] = meta.stack_uri.to_s
      else
        raise CuffBase::InvokationError, 'Only HTTPS URLs pointing to amazonaws.com supported.'
      end
    elsif meta.stack_uri.scheme == 'file'
      file = meta.stack_uri.to_s.sub(/^file:\/+/, '/')
      template = self.load_minified_template(file)
      if template.size <= 51200
        template_parameters[:template_body] = template
      end
    else
      raise CuffBase::InvokationError, "Unsupported scheme #{meta.stack_uri.scheme}"
    end

    template_parameters
  end
end
