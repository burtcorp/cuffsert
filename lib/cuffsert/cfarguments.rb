require 'open-uri'
require 'yaml'
require 'cuffsert/yaml-ext'

# TODO:
# - propagate timeout here (from config?)
# - creation change-set: cfargs[:change_set_type] = 'CREATE'

module CuffSert
  TIMEOUT = 10

  def self.as_cloudformation_args(meta)
    cfargs = {
      :stack_name => meta.stackname,
      :capabilities => %w[
        CAPABILITY_AUTO_EXPAND
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

    if meta.stack_uri
      cfargs.merge!(self.template_parameters(meta))
    end
    cfargs
  end

  def self.as_create_stack_args(meta)
    no_value = meta.parameters.select {|_, v| v.nil? }.keys
    raise "Supply value for #{no_value.join(', ')}" unless no_value.empty?

    cfargs = self.as_cloudformation_args(meta)
    cfargs[:timeout_in_minutes] = TIMEOUT
    cfargs[:on_failure] = 'DELETE'
    cfargs
  end

  def self.as_update_change_set(meta, stack)
    cfargs = self.as_cloudformation_args(meta)
    cfargs[:change_set_name] = meta.stackname
    cfargs[:change_set_type] = 'UPDATE'
    if cfargs[:use_previous_template] = meta.stack_uri.nil?
      Array(stack[:parameters]).each do |param|
        key = param[:parameter_key]
        unless meta.parameters.include?(key)
          cfargs[:parameters] ||= []
          cfargs[:parameters] << {:parameter_key => key, :use_previous_value => true}
        end
      end
      if !meta.tags.empty?
        Array(stack[:tags]).each do |tag|
          unless meta.tags.include?(tag[:key])
            cfargs[:tags] << tag
          end
        end
      end
    end
    cfargs
  end

  def self.as_delete_stack_args(stack)
    { :stack_name => stack[:stack_id] }
  end

  def self.s3_uri_to_https(uri, region)
    bucket = uri.host
    key = uri.path
    host = region == 'us-east-1' ? 's3.amazonaws.com' : "s3-#{region}.amazonaws.com"
    "https://#{host}/#{bucket}#{key}"
  end

  def self.load_template(stack_uri)
    file = stack_uri.to_s.sub(/^file:\/+/, '/')
    YAML.load(open(file).read)
  end

  private_class_method

  def self.template_parameters(meta)
    template_parameters = {}

    if meta.stack_uri.scheme == 's3'
      template_parameters[:template_url] = self.s3_uri_to_https(meta.stack_uri, meta.aws_region)
    elsif meta.stack_uri.scheme == 'https'
      if meta.stack_uri.host.end_with?('amazonaws.com')
        template_parameters[:template_url] = meta.stack_uri.to_s
      else
        raise 'Only HTTPS URLs pointing to amazonaws.com supported.'
      end
    elsif meta.stack_uri.scheme == 'file'
      template = CuffSert.load_template(meta.stack_uri).to_json
      if template.size <= 51200
        template_parameters[:template_body] = template
      end
    else
      raise "Unsupported scheme #{meta.stack_uri.scheme}"
    end

    template_parameters
  end
end
