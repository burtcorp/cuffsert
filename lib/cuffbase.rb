require 'yaml'

module CuffBase
  def self.shared_cli_args(opts, args)
    opts.on('--region=aws_region', 'AWS region, overrides env variable AWS_REGION') do |region|
      args[:aws_region] = region
    end
  end

  def self.empty_from_template(io)
    self.template_parameters(io) {|_| nil }
  end

  def self.defaults_from_template(io)
    self.template_parameters(io) {|data| data['Default'] }
  end

  private_class_method

  def self.template_parameters(io, &block)
    template = YAML.load(io)
    parameters = {}
    (template['Parameters'] || []).each do |key, data|
      parameters[key] = block.call(data)
    end
    parameters
  end
end
