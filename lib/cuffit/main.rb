require 'cuff/metadata'
require 'cuffsert/rxcfclient'
require 'cuffit/cli_args'

module Cuff
  def self.new_meta(cli_args)
    default = self.meta_defaults(cli_args)
    meta = yield default
    Cuff.cli_overrides(meta, cli_args)
  end
end

module CuffIt
  def self.extract_from_stack(stack)
    {
      :tags => (stack[:tags] || [])
        .each_with_object({}) do |t, o|
          o[t[:key]] = t[:value]
        end,
      :parameters => (stack[:parameters] || [])
        .each_with_object({}) do |p, o|
          o[p[:parameter_key]] = p[:parameter_value]
        end
    }
  end

  def self.extract_from_template(io)
    template = YAML.load(io)
    (template['Parameters'] || []).each_with_object({}) do |(k, v), o|
      o[k] = v['Default']
    end
  end

  def self.update_meta_from_stack(meta)
    stack = client.find_stack_blocking(meta)
    raise "Could not find stack #{meta.stackname}" if stack.nil?
    stack_data = self.extract_from_stack(stack)
    meta.update_from(stack_data)
  end

  def self.apply_meta(config, meta)
    config = config || {'Format' => 'v1'}
    meta.parameters.map do |(k, v)|
      config['Parameters'] ||= []
      config['Parameters'] << {'Name' => k, 'Value' => v}
    end
    config
  end

  def self.run(argv, client: RxCFClient.new)
    cli_args = CuffIt.cli_args(argv)
    stack_path = cli_args[:stack_path][0]
    meta = Cuff.build_meta(cli_args)
    stack = client.find_stack_blocking(meta)
    stack_params = CuffIt.extract_from_stack(stack)
    default_params = CuffIt.extract_from_template(open(stack_path))
    merged_params = self.merge_parameters(
      default_params,
      meta.parameters,
      stack_params,
      cli_args[:overrides]
    )
  end
end
