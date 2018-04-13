require 'cuffsert/actions'
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
  def self.determine_action(meta, force_replace: false, cfclient: RxCFClient.new)
    found = cfclient.find_stack_blocking(meta)

    if found && INPROGRESS_STATES.include?(found[:stack_status])
      action = Abort.new('Stack operation already in progress')
    else
      if found.nil?
        action = CreateStackAction.new(meta, nil)
      elsif found[:stack_status] == 'ROLLBACK_COMPLETE' || force_replace
        action = RecreateStackAction.new(meta, found)
      else
        action = UpdateStackAction.new(meta, found)
      end
      action.cfclient = cfclient
      yield action
    end
    action
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
    action = CuffSert.determine_action(meta, force_replace: cli_args[:force_replace]) do |a|
      a.confirmation = CuffSert.method(:confirmation)
    end
    renderer = CuffSert.make_renderer(cli_args)
    RendererPresenter.new(action.as_observable, renderer)
  end
end
