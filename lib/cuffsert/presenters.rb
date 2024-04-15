require 'aws-sdk-cloudformation'
require 'cuffsert/cfstates'
require 'cuffsert/errors'
require 'cuffsert/messages'

module CuffSert
  class BasePresenter
    def initialize(events)
      events.subscribe(
        method(:on_event),
        method(:on_error),
        method(:on_complete)
      )
    end

    def on_error(err)
      STDERR.puts'Error:'
      STDERR.puts err
      STDERR.puts err.backtrace.join("\n\t")
    end

    def on_complete
    end

    def update_width(width)
    end
  end

  class RawPresenter < BasePresenter
    def on_event(event)
      puts event.inspect
    end

    def on_complete
      puts 'Done.'
    end
  end

  class RendererPresenter < BasePresenter
    def initialize(events, renderer)
      @resources = []
      @index = {}
      @renderer = renderer
      super(events)
    end

    def on_event(event)
      case event
      when ::CuffSert::Templates
        @renderer.templates(*event.message)
      when Aws::CloudFormation::Types::StackEvent
        on_stack_event(event)
      when ::CuffSert::ChangeSet
        on_change_set(event.message)
      # when [:recreate, Aws::CloudFormation::Types::Stack]
      when Array
        on_stack(*event)
      when ::CuffSert::Report
        @renderer.report(event)
      when ::CuffSert::Abort
        @renderer.abort(event)
      when ::CuffSert::Done
        @renderer.done(event)
      when ::CuffSert::Message
        puts event.message
      else
        puts event
      end
    end

    def on_error(err)
      case err
      when CuffSertError
        @renderer.abort(err)
      else
        super(err)
      end
      exit(1)
    end

    def on_complete
    end

    private

    def on_change_set(change_set)
      @renderer.change_set(change_set.to_h)
    end

    def on_stack_event(event)
      resource = lookup_stack_resource(event)
      update_resource_states(resource, event)
      @renderer.event(event, resource)
      @renderer.clear
      @resources.each { |resource| @renderer.resource(resource) }
      clear_resources if is_completed_stack_event(event)
    end

    def on_stack(event, stack)
      @renderer.stack(event, stack)
    end

    def lookup_stack_resource(event)
      rid = event[:logical_resource_id]
      unless (pos = @index[rid])
        pos = @index[rid] = @resources.size
        @resources << make_resource(event)
      end
      @resources[pos]
    end

    def make_resource(event)
      event.to_h
        .reject { |k, _| k == :timestamp }
        .merge!(:states => [])
    end

    def update_resource_states(resource, event)
      resource[:states] = resource[:states]
        .reject { |state| state == :progress }
        .take(1) << CuffSert.state_category(event[:resource_status])
    end

    def is_completed_stack_event(event)
      event[:resource_type] == 'AWS::CloudFormation::Stack' &&
        FINAL_STATES.include?(event[:resource_status])
    end

    def clear_resources
      @resources.clear
      @index.clear
    end
  end
end
