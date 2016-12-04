require 'cuffsert/cli_args'

module CuffSert

def self.build_meta(cli_args)
  config = CuffSert.load_config(cli_args[:metadata_path])
  meta = CuffSert.meta_for_path(config, cli_args[:selector])
  meta.update_from(cli_args[:overrides])
end

def self.execute(meta)
  sources = []
  client = RxCFClient.new
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
  events = CuffSert.execute(meta)
  # present events
end

end