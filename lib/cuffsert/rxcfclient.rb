require 'aws-sdk'
require 'cuffsert/cfstates'
require 'rx'

# TODO:
# - look only at events that occurred recently
# - throttle describe_stack_events calls
# - retry on "5xx" errors
# - handle pagination

module CuffSert
  class RxCFClient
    def initialize(aws_cf)
      @cf = aws_cf
    end

    def find_stack_blocking(meta)
      name = meta.stackname
      stacks = @cf.describe_stacks(stack_name: name)['Stacks']
      return nil if stacks.empty?
      stacks[0]
    end

    def create_stack(stack)
      eventid_cache = Set.new
      Rx::Observable.create do |observer|
        state = @cf.create_stack(stack)['Stacks'][0]
        stack_events(state) do |event|
          observer.on_next(event)
        end
        observer.on_completed
      end
      .select do |event|
        eventid_cache.add?(event['EventId'])
      end
    end

    def update_stack(stack)
    end

    def delete_stack(stack)
    end

    private

    def stack_finished?(state)
      FINAL_STATES.include?(state['StackStatus'])
    end

    def stack_events(state)
      name = state['StackName']
      loop do
        for event in @cf.describe_stack_events(stack_name: name)['StackEvents']
          yield event
        end
        break if stack_finished?(state)
        state = @cf.describe_stacks(stack_name: name)['Stacks'][0]
      end
    end
  end
end
