require 'cuffsert/actions'
require 'cuffsert/cfarguments'
require 'cuffsert/messages'
require 'rx'

module CuffSert
  class BaseAction
    attr_accessor :cfclient, :confirmation

    def initialize(meta, stack)
      @cfclient = nil
      @confirmation = nil
      @meta = meta
      @stack = stack
    end
  end

  class CreateStackAction < BaseAction
    def as_observable
      cfargs = CuffSert.as_create_stack_args(@meta)
      Rx::Observable.concat(
        Rx::Observable.of([:create, @meta.stackname]),
        Rx::Observable.defer do
          if @confirmation.call(@meta, :create, nil)
            @cfclient.create_stack(cfargs)
          else
            Abort.new('User abort!').as_observable
          end
        end
      )
    end
  end

  class UpdateStackAction < BaseAction
    def as_observable
      cfargs = CuffSert.as_update_change_set(@meta)
      @cfclient.prepare_update(cfargs)
        .last
        .flat_map do |change_set|
          Rx::Observable.concat(
            Rx::Observable.of(change_set),
            Rx::Observable.defer {
              if change_set[:status] == 'FAILED'
                @cfclient.abort_update(change_set[:change_set_id])
              elsif @confirmation.call(@meta, :update, change_set)
                @cfclient.update_stack(change_set[:stack_id], change_set[:change_set_id])
              else
                Rx::Observable.concat(
                  @cfclient.abort_update(change_set[:change_set_id]),
                  Abort.new('User abort!').as_observable
                )
              end
            }
          )
        end
    end
  end

  class RecreateStackAction < BaseAction
    def as_observable
      crt_args = CuffSert.as_create_stack_args(@meta)
      del_args = CuffSert.as_delete_stack_args(@stack)
      Rx::Observable.concat(
        Rx::Observable.of([:recreate, @stack]),
        Rx::Observable.defer do
          if @confirmation.call(@meta, :recreate, @stack)
            Rx::Observable.concat(
              @cfclient.delete_stack(del_args),
              @cfclient.create_stack(crt_args)
            )
          else
            CuffSert::Abort.new('User abort!').as_observable
          end
        end
      )
    end
  end
end
