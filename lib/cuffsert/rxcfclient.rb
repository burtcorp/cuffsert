require 'aws-sdk-cloudformation'
require 'cuffsert/cfstates'
require 'cuffsert/errors'
require 'yaml'
require 'rx'

module CuffSert
  class RxCFClient
    def initialize(aws_region = nil, **options)
      initargs = {retry_limit: 8}
      initargs[:region] = aws_region if aws_region
      @cf = options[:aws_cf] || Aws::CloudFormation::Client.new(initargs)
      @max_items = options[:max_items] || 1000
      @pause = options[:pause] || 5
    end

    def find_stack_blocking(meta)
      name = meta.stackname
      @cf.describe_stacks(stack_name: name)[:stacks][0]
    rescue Aws::CloudFormation::Errors::ValidationError
      nil
    end

    def get_template(meta)
      Rx::Observable.create do |observer|
        template = @cf.get_template(:stack_name => meta.stackname)
        observer.on_next(YAML.load(template[:template_body]))
        observer.on_completed
      end
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
          if FINAL_STATES.include?(change_set.data[:status])
            observer.on_next(change_set.data)
            break
          end
        end
        observer.on_completed
      end
    end

    def update_stack(stack_id, change_set_id)
      Rx::Observable.create do |observer|
        start_time = record_start_time
        @cf.execute_change_set(change_set_name: change_set_id)
        begin
          stack_events(stack_id, start_time) do |event|
            observer.on_next(event)
          end
        rescue => e
          observer.on_error(e)
        end
        observer.on_completed
      end
    end

    def abort_update(change_set_id)
      Rx::Observable.create do |observer|
        @cf.delete_change_set(change_set_name: change_set_id)
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
      return false unless event[:physical_resource_id] == stack_id
      case CuffSert.state_category(event[:resource_status])
      when :bad
        raise RxCFError, "Stack #{event.logical_resource_id} finished in state #{event.resource_status}"
      when :good
        true
      else
        false
      end
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
