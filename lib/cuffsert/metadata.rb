require 'yaml'

module CuffSert
  class StackConfig
    attr_accessor :stackname, :selected_path, :dangerous_ok, :stack_uri
    attr_accessor :suffix, :parameters, :tags

    def initialize
      @selected_path = []
      @dangerous_ok = false
      @parameters = {}
      @tags = {}
    end

    def append_path(lmnt)
      @selected_path << lmnt
    end

    def update_from(metadata)
      @stackname = metadata[:stackname] || @stackname
      @suffix = metadata[:suffix] || @suffix
      @parameters.merge!(metadata[:parameters] || {})
      @tags.merge!(metadata[:tags] || {})
      self
    end

    def stackname
      @stackname || (@selected_path + [*@suffix]).join('-')
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
    variants = metadata[:variants]
    if key.nil?
      raise "No DefaultPath found for #{variants.keys}" unless variants.nil?
      return target
    end
    target.append_path(key)

    raise "Missing variants section as expected by #{key}" if variants.nil?
    new_meta = variants[key.to_sym]
    raise "#{key.inspect} not found in variants" if new_meta.nil?
    self.meta_for_path(new_meta, path, target)
  end

  def self.build_meta(cli_args)
    io = open(cli_args[:metadata])
    config = CuffSert.load_config(io)
    default = self.meta_defaults(cli_args)
    meta = CuffSert.meta_for_path(config, cli_args[:selector], default)
    meta.update_from(cli_args[:overrides])
  end

  private_class_method

  def self.meta_defaults(cli_args)
    default = StackConfig.new
    default.suffix = File.basename(cli_args[:metadata], '.yml')
    default
  end

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
