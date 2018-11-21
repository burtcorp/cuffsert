require 'cuffsert/actions'
require 'cuffsert/cfstates'
require 'cuffsert/cli_args'
require 'cuffsert/confirmation'
require 'cuffsert/messages'
require 'cuffsert/metadata'
require 'cuffsert/presenters'
require 'cuffsert/rxcfclient'
require 'cuffsert/rxs3client'
require 'rx'
require 'uri'

module CuffSert
  def self.determine_action(meta, cfclient, force_replace: false)
    stack, change_set = cfclient.find_stack_blocking(meta)

    if stack && INPROGRESS_STATES.include?(stack[:stack_status])
      action = Abort.new('Stack operation already in progress')
    else
      if stack.nil?
        action = CreateStackAction.new(meta, nil)
      elsif stack[:stack_status] == 'ROLLBACK_COMPLETE' || force_replace
        action = RecreateStackAction.new(meta, stack)
      else
        action = UpdateStackAction.new(meta, stack, change_set)
      end
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
    cfclient = RxCFClient.new(meta.aws_region)
    action = CuffSert.determine_action(meta, cfclient, force_replace: cli_args[:force_replace]) do |a|
      a.confirmation = CuffSert.method(:confirmation)
      a.s3client = RxS3Client.new(cli_args, meta.aws_region) if cli_args[:s3_upload_prefix]
      a.cfclient = cfclient
    end
    action.validate!
    renderer = CuffSert.make_renderer(cli_args)
    RendererPresenter.new(action.as_observable, renderer)
  end
end
