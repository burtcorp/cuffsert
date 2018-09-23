require 'cuffbase'
require 'yaml'

module CuffSert
  class StackConfig
    attr_accessor :stackname, :selected_path, :op_mode, :stack_uri
    attr_accessor :suffix, :parameters, :tags

    def initialize
      @selected_path = []
      @op_mode = :normal
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

  def self.validate_and_urlify(stack_path)
    if stack_path =~ /^[A-Za-z0-9]+:/
      stack_uri = URI.parse(stack_path)
    else
      normalized = File.expand_path(stack_path)
      unless File.exist?(normalized)
        raise "Local file #{normalized} does not exist"
      end
      stack_uri = URI.join('file:///', normalized)
    end
    unless ['s3', 'file'].include?(stack_uri.scheme)
      raise "Uri #{stack_uri.scheme} is not supported"
    end
    stack_uri
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
    candidate, *path = path
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
    default = self.meta_defaults(cli_args)
    config = self.metadata_if_present(cli_args)
    meta = CuffSert.meta_for_path(config, cli_args[:selector], default)
    CuffSert.cli_overrides(meta, cli_args)
  end

  private_class_method

  def self.meta_defaults(cli_args)
    stack_path = (cli_args[:stack_path] || [])[0]
    if stack_path && File.exists?(stack_path)
      nil_params = CuffBase.empty_from_template(open(stack_path))
    else
      nil_params = {}
    end
    default = StackConfig.new
    default.update_from({:parameters => nil_params})
    default.suffix = File.basename(cli_args[:metadata], '.yml') if cli_args[:metadata]
    default
  end

  def self.metadata_if_present(cli_args)
    if cli_args[:metadata]
      io = open(cli_args[:metadata])
      CuffSert.load_config(io)
    else
      {}
    end
  end

  def self.cli_overrides(meta, cli_args)
    meta.update_from(cli_args[:overrides])
    meta.op_mode = cli_args[:op_mode] || meta.op_mode
    if (stack_path = (cli_args[:stack_path] || [])[0])
      meta.stack_uri = CuffSert.validate_and_urlify(stack_path)
    end
    meta
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
