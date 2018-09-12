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
      if needs_template_upload?(cfargs)
        raise 'Template bigger than 51200; please supply --s3-upload-prefix' unless @s3client
        uri, progress = @s3client.upload(@meta.stack_uri)
        [CuffSert.s3_uri_to_https(uri).to_s, progress]
      else
        [nil, Rx::Observable.empty]
      end
    end

    private

    def needs_template_upload?(cfargs)
      cfargs[:template_body].nil? &&
        cfargs[:template_url].nil? &&
        !cfargs[:use_previous_template]
    end
  end

  class CreateStackAction < BaseAction
    def validate!
      if @meta.stack_uri.nil?
        raise "You need to pass a template to create #{@meta.stackname}" # in #{@meta.aws_region}."
      end
    end

    def as_observable
      cfargs = CuffSert.as_create_stack_args(@meta)
      upload_uri, maybe_upload = upload_template_if_oversized(cfargs)
      cfargs[:template_url] = upload_uri if upload_uri
      maybe_upload.concat(
        Rx::Observable.of([:create, @meta.stackname]),
        Rx::Observable.defer do
          if @confirmation.call(@meta, :create, nil)
            Rx::Observable.concat(
              @cfclient.create_stack(cfargs),
              Done.new.as_observable
            )
          else
            Abort.new('User abort!').as_observable
          end
        end
      )
    end
  end

  class UpdateStackAction < BaseAction
    def validate!
      if @meta.stack_uri.nil?
        if @meta.parameters.empty? && @meta.tags.empty?
          raise "Stack update without template needs at least one parameter (-p) or tag (-t)."
        end
      end
    end

    def as_observable
      cfargs = CuffSert.as_update_change_set(@meta, @stack)
      upload_uri, maybe_upload = upload_template_if_oversized(cfargs)
      cfargs[:template_url] = upload_uri if upload_uri
      maybe_upload
        .concat(@cfclient.prepare_update(cfargs).map {|change_set| CuffSert::ChangeSet.new(change_set) })
        .flat_map(&method(:on_event))
    end

    private

    def on_event(event)
      Rx::Observable.concat(
        Rx::Observable.just(event),
        Rx::Observable.defer do
          case event
          when CuffSert::ChangeSet
            on_changeset(event.message)
          else
            Rx::Observable.empty
          end
        end
      )
    end

    def on_changeset(change_set)
      if change_set[:status] == 'FAILED'
        message = "Update failed: #{change_set[:status_reason]}"
        @cfclient.abort_update(change_set[:change_set_id])
          .concat(Abort.new(message).as_observable)
      elsif @confirmation.call(@meta, :update, change_set)
        @cfclient.update_stack(change_set[:stack_id], change_set[:change_set_id])
          .concat(Done.new.as_observable)
      else
        @cfclient.abort_update(change_set[:change_set_id])
          .concat(Abort.new('User abort!').as_observable)
      end
    end
  end

  class RecreateStackAction < BaseAction
    def validate!
      if @meta.stack_uri.nil?
        raise "You need to pass a template to re-create #{@meta.stackname}" # in #{@meta.aws_region}."
      end
    end

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
              @cfclient.create_stack(crt_args),
              Done.new.as_observable
            )
          else
            CuffSert::Abort.new('User abort!').as_observable
          end
        end
      )
    end
  end
end
