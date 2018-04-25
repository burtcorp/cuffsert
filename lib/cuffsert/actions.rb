require 'cuffsert/actions'
require 'cuffsert/cfarguments'
require 'cuffsert/messages'
require 'rx'

module CuffSert
  class BaseAction
    attr_accessor :cfclient, :confirmation, :s3client

    def initialize(meta, stack)
      @cfclient = nil
      @confirmation = nil
      @meta = meta
      @s3client = nil
      @stack = stack
    end

    def upload_template_if_oversized(cfargs)
      if cfargs[:template_body].nil? && cfargs[:template_url].nil?
        raise 'Template bigger than 51200; please supply --s3-upload-prefix' unless @s3client
        uri, progress = @s3client.upload(@meta.stack_uri)
        [CuffSert.s3_uri_to_https(uri).to_s, progress]
      else
        [nil, Rx::Observable.empty]
      end
    end
  end

  class CreateStackAction < BaseAction
    def as_observable
      cfargs = CuffSert.as_create_stack_args(@meta)
      upload_uri, maybe_upload = upload_template_if_oversized(cfargs)
      cfargs[:template_url] = upload_uri if upload_uri
      maybe_upload.concat(
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
      upload_uri, maybe_upload = upload_template_if_oversized(cfargs)
      cfargs[:template_url] = upload_uri if upload_uri
      maybe_upload
        .concat(@cfclient.prepare_update(cfargs))
        .flat_map do |change_set|
          if change_set.is_a? Aws::CloudFormation::Types::DescribeChangeSetOutput
            Rx::Observable.concat(
              Rx::Observable.of(change_set),
              Rx::Observable.defer {
                if change_set[:status] == 'FAILED'
                  Rx::Observable.concat(
                    @cfclient.abort_update(change_set[:change_set_id]),
                    Abort.new("Update failed: #{change_set[:status_reason]}").as_observable
                  )
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
          else
            Rx::Observable.just(change_set)
          end
        end
    end
  end

  class RecreateStackAction < BaseAction
    def as_observable
      crt_args = CuffSert.as_create_stack_args(@meta)
      del_args = CuffSert.as_delete_stack_args(@stack)
      upload_uri, maybe_upload = upload_template_if_oversized(crt_args)
      crt_args[:template_url] = upload_uri if upload_uri
      maybe_upload.concat(
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
