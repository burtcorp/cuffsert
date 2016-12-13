require 'cuffsert/cfarguments'
require 'cuffsert/cfstates'
require 'cuffsert/cli_args'
require 'cuffsert/metadata'
require 'cuffsert/presenters'
require 'cuffsert/rxcfclient'
require 'rx'
require 'uri'

# TODO:
# - Stop using file: that we anyway need to special-case in cfarguments
# - default value for meta.metadata when stack_path is local file
# - selector and metadata are mandatory and need guards accordingly
# - validate_and_urlify belongs in metadata.rb
# - execute should use helpers and not know details of statuses

module CuffSert
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

  def self.execute(meta, client: RxCFClient.new)
    sources = []
    found = client.find_stack_blocking(meta)

    if found && INPROGRESS_STATES.include?(found[:stack_status])
      raise 'Stack operation already in progress'
    end

    if found && found[:stack_status] == 'ROLLBACK_COMPLETE'
      cfargs = CuffSert.as_delete_stack_args(meta)
      sources << client.delete_stack(cfargs)
      found = nil
    end

    if found
      cfargs = CuffSert.as_update_stack_args(meta)
      sources << client.update_stack(cfargs)
    else
      cfargs = CuffSert.as_create_stack_args(meta)
      sources << client.create_stack(cfargs)
    end
    Rx::Observable.concat(*sources)
  end

  def self.run(argv)
    cli_args = CuffSert.parse_cli_args(argv)
    meta = CuffSert.build_meta(cli_args)
    if cli_args[:stack_path].nil? || cli_args[:stack_path].size != 1
      raise 'Requires exactly one stack path'
    end
    stack_path = cli_args[:stack_path][0]
    meta.stack_uri = CuffSert.validate_and_urlify(stack_path)
    events = CuffSert.execute(meta)
    RawPresenter.new(events)
  end
end
