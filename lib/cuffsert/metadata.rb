require 'yaml'

module CuffSert
  class StackConfig
    attr_accessor :stackname, :selected_path, :parameters, :tags
    def initialize
      @selected_path = []
      @parameters = {}
      @tags = {}
    end

    def append_path(lmnt)
      @selected_path << lmnt
    end

    def update_from(metadata)
      @stackname = metadata[:stackname] || @stackname
      @parameters.merge!(metadata[:parameters] || {})
      @tags.merge!(metadata[:tags] || {})
    end

    def stackname
      @stackname || @selected_path.join('-')
    end
  end

  def self.load_config(io)
    config = YAML.load(io)
    raise 'config does not seem to be a YAML hash?' unless config.is_a?(Hash)
    config = symbolize_keys(config)
    format = config.delete(:format)
    raise 'Please include Format: v1' if format.nil? || format.downcase != 'v1'
    config
  end

  def self.meta_for_path(metadata, path, target = StackConfig.new)
    target.update_from(metadata)
    candidate, path = path
    key = candidate || metadata[:defaultpath]
    return target if key.nil?
    target.append_path(key)

    variants = metadata[:variants]
    raise "Missing variants section as expected by #{key}" if variants.nil?
    new_meta = variants[key.to_sym]
    raise "#{key.inspect} not found in variants" if new_meta.nil?
    self.meta_for_path(new_meta, path, target)
  end

  private_class_method

  def self.symbolize_keys(hash)
    hash.each_with_object({}) do |(k, v), h|
      k = k.downcase.to_sym
      if k == :tags || k == :parameters
        h[k] = v.each_with_object({}) { |e, h| h[e['Name']] = e['Value'] }
      else
        h[k] = v.is_a?(Hash) ? symbolize_keys(v) : v
      end
    end
  end
end
