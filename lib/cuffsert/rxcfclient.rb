require 'aws-sdk'
require 'cuffsert/cfstates'
require 'rx'

module CuffSert
  class RxCFClient
    def initialize(
        aws_cf = Aws::CloudFormation::Client.new(retry_limit: 8),
        pause: 5,
        max_items: 1000)
      @cf = aws_cf
      @max_items = max_items
      @pause = pause
    end

    def find_stack_blocking(meta)
      name = meta.stackname
      @cf.describe_stacks(stack_name: name)[:stacks][0]
    rescue Aws::CloudFormation::Errors::ValidationError
      nil
    end

    def create_stack(cfargs)
      Rx::Observable.create do |observer|
        start_time = record_start_time
        stack_id = @cf.create_stack(cfargs)[:stack_id]
        stack_events(stack_id, start_time) do |event|
          observer.on_next(event)
        end
        observer.on_completed
      end
    end

    def prepare_update(cfargs)
      Rx::Observable.create do |observer|
        change_set_id = @cf.create_change_set(cfargs)[:id]
        loop do
          change_set = @cf.describe_change_set(change_set_name: change_set_id)
          observer.on_next(change_set)
          break if FINAL_STATES.include?(change_set[:status])
        end
        observer.on_completed
      end
    end

    def update_stack(stack_id, change_set_id)
      Rx::Observable.create do |observer|
        start_time = record_start_time
        @cf.execute_change_set(change_set_name: change_set_id)
        stack_events(stack_id, start_time) do |event|
          observer.on_next(event)
        end
        observer.on_completed
      end
    end

    def delete_stack(cfargs)
      eventid_cache = Set.new
      Rx::Observable.create do |observer|
        start_time = record_start_time
        @cf.delete_stack(cfargs)
        stack_events(cfargs[:stack_name], start_time) do |event|
          observer.on_next(event)
        end
        observer.on_completed
      end
      .select do |event|
        eventid_cache.add?(event[:event_id])
      end
    end

    private

    def record_start_time
      # Please make sure your machine has NTP :p
      DateTime.now - 5.0 / 86400
    end

    def stack_finished?(stack_id, event)
      event[:physical_resource_id] == stack_id &&
        FINAL_STATES.include?(event[:resource_status])
    end

    def flatten_events(stack_id)
      @cf.describe_stack_events(stack_name: stack_id).each do |events|
        for event in events[:stack_events]
          yield event
        end
      end
    end

    def stack_events(stack_id, start_time)
      eventid_cache = Set.new
      loop do
        events = []
        done = false
        flatten_events(stack_id) do |event|
          break if event[:timestamp].to_datetime < start_time
          next unless eventid_cache.add?(event[:event_id])
          events.unshift(event)
          done = true if stack_finished?(stack_id, event)
        end
        events.each { |event| yield event }
        break if done
        sleep(@pause)
      end
    end
  end
end
