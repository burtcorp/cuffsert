require 'cuffsert/cli_args'
require 'cuffsert/metadata'
require 'rx'
require 'uri'

module CuffSert

def self.build_meta(cli_args)
  io = open(cli_args[:metadata_path])
  config = CuffSert.load_config(io)
  meta = CuffSert.meta_for_path(config, cli_args[:selector])
  meta.update_from(cli_args[:overrides])
end

def self.validate_and_urlify(stack_path)
  if stack_path =~ /^[A-Za-z0-9]+:/
    stack_url = URI.parse(stack_path)
  else
    normalized = File.expand_path(stack_path)
    unless File.exist?(normalized)
      raise "Local file #{normalized} does not exist"
    end
    stack_url = URI.join('file:///', normalized)
  end
  unless ['s3', 'file'].include?(stack_url.scheme)
    raise "Uri #{stack_url.scheme} is not supported"
  end
  stack_url
end

def self.execute(meta, client: RxCFClient.new)
  sources = []
  found = client.find_stack_blocking(meta['stackname'])

  if found && found['StackStatus'] == 'ROLLBACK_COMPLETE'
    sources << client.delete_stack(meta)
    found = nil
  end

  if found
    sources << client.update_stack(meta)
  else
    sources << client.create_stack(meta)
  end
  Rx::Observable.concat(*sources)
end

def self.run(argv)
  cli_args = CuffSert.parse_cli_args(argv)
  meta = CuffSert.build_metadata(cli_args)
  meta[:stack_uri] = CuffSert.validate_and_urlify(meta[:stack_path])
  events = CuffSert.execute(meta)
  # present events
end

end
