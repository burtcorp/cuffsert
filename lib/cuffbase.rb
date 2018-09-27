require 'yaml'

module CuffBase
  class InvokationError < StandardError ; end

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
