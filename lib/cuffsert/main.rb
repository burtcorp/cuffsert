require 'cuffsert/cfarguments'
require 'cuffsert/cfstates'
require 'cuffsert/cli_args'
require 'cuffsert/confirmation'
require 'cuffsert/messages'
require 'cuffsert/metadata'
require 'cuffsert/presenters'
require 'cuffsert/rxcfclient'
require 'rx'
require 'uri'

module CuffSert
  def self.create_stack(client, meta, confirm_create)
    cfargs = CuffSert.as_create_stack_args(meta)
    Rx::Observable.concat(
      Rx::Observable.of([:create, meta.stackname]),
      Rx::Observable.defer do
        if confirm_create.call(meta, :create, nil)
          client.create_stack(cfargs)
        else
          Abort.new('User abort!').as_observable
        end
      end
    )
  end

  def self.update_stack(client, meta, confirm_update)
    cfargs = CuffSert.as_update_change_set(meta)
    client.prepare_update(cfargs)
      .last
      .flat_map do |change_set|
        Rx::Observable.concat(
          Rx::Observable.of(change_set),
          Rx::Observable.defer {
            if change_set[:status] == 'FAILED'
              client.abort_update(change_set[:change_set_id])
            elsif confirm_update.call(meta, :update, change_set)
              client.update_stack(change_set[:stack_id], change_set[:change_set_id])
            else
              Rx::Observable.concat(
                client.abort_update(change_set[:change_set_id]),
                Abort.new('User abort!').as_observable
              )
            end
          }
        )
      end
  end

  def self.recreate_stack(client, stack, meta, confirm_recreate)
    crt_args = CuffSert.as_create_stack_args(meta)
    del_args = CuffSert.as_delete_stack_args(stack)
    Rx::Observable.concat(
      Rx::Observable.of([:recreate, stack]),
      Rx::Observable.defer do
        if confirm_recreate.call(meta, :recreate, stack)
          Rx::Observable.concat(
            client.delete_stack(del_args),
            client.create_stack(crt_args)
          )
        else
          CuffSert::Abort.new('User abort!').as_observable
        end
      end
    )
  end

  def self.execute(meta, confirm_update, force_replace: false, client: RxCFClient.new)
    sources = []
    found = client.find_stack_blocking(meta)

    if found && INPROGRESS_STATES.include?(found[:stack_status])
      sources << Abort.new('Stack operation already in progress').as_observable
    elsif found.nil?
      sources << self.create_stack(client, meta, confirm_update)
    elsif found[:stack_status] == 'ROLLBACK_COMPLETE' || force_replace
      sources << self.recreate_stack(client, found, meta, confirm_update)
    else
      sources << self.update_stack(client, meta, confirm_update)
    end
    Rx::Observable.concat(*sources)
  end

  def self.make_renderer(cli_args)
    if cli_args[:output] == :json
      JsonRenderer.new(STDOUT, STDERR, cli_args)
    else
      ProgressbarRenderer.new(STDOUT, STDERR, cli_args)
    end
  end

  def self.run(argv)
    cli_args = CuffSert.parse_cli_args(argv)
    CuffSert.validate_cli_args(cli_args)
    meta = CuffSert.build_meta(cli_args)
    events = CuffSert.execute(meta, CuffSert.method(:confirmation),
      force_replace: cli_args[:force_replace])
    renderer = CuffSert.make_renderer(cli_args)
    RendererPresenter.new(events, renderer)
  end
end
