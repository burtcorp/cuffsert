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
      :tags => stack[:tags]
        .each_with_object({}) do |t, o|
          o[t[:key]] = t[:value]
        end,
      :parameters => stack[:parameters]
        .each_with_object({}) do |p, o|
          o[p[:parameter_key]] = t[:parameter_value]
        end
    }
  end

  def self.update_meta_from_stack(meta)
    stack = client.find_stack_blocking(meta)
    raise "Could not find stack #{meta.stackname}" if stack.nil?
    stack_data = self.extract_from_stack(stack)
    meta.update_from(stack_data)
  end

  def self.apply_meta(config, meta)

  end

  def self.run(argv, client: RxCFClient.new)
    cli_args = CuffIt.cli_args(argv)
    meta = Cuff.new_meta(cli_args, &CuffIt.method(:update_meta_from_stack))
    Cuff.update_config(meta)
  end
end
