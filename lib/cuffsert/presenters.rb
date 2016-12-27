require 'aws-sdk'
require 'colorize'
require 'cuffsert/cfstates'
require 'rx'

# TODO: Animate in-progress states
# def initialize(
#     events,
#     strobe: Rx::Observable.just(0).concat(Rx::Observable.interval(0.5)),
#     renderer: ProgressbarRenderer.new
#   )
#   @resources = []
#   @index = {}
#   @renderer = renderer
#   super(Rx::Observable.combine_latest(strobe, events) { |n, event|
#     [event, n]
#   })
# end


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

    def on_event((event, n))
      case event
      when Aws::CloudFormation::Types::StackEvent
        on_stack_event(event, n)
      else
        puts event
      end
    end

    def on_complete
      @renderer.done
    end

    private

    def on_stack_event(event, n)
      resource = lookup_stack_resource(event)
      update_resource_states(resource, event)
      @renderer.event(event, resource)
      @renderer.clear
      @resources.each { |resource| @renderer.resource(resource) }
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
      resource[:states] = resource[:states].reject do |state|
        state == :progress
      end << CuffSert.state_category(event[:resource_status])
    end
  end

  class ProgressbarRenderer
    def initialize(output = STDOUT)
      @output = output
    end

    def event(event, resource)
      if resource[:states][-1] == :bad
        @output.write("\r")
        puts event
      end
    end

    def clear
      @output.write("\r")
    end

    def resource(resource)
      color, symbol = case resource[:states]
      when [:progress]
        [:yellow, :tripple_dot]
      when [:good]
        [:green, :check]
      when [:bad]
        [:red, :cross]
      when [:good, :progress]
        [:light_white, :tripple_dot]
      when [:bad, :progress]
        [:red, :tripple_dot]
      when [:good, :good], [:bad, :good]
        [:light_white, :check]
      when [:good, :bad], [:bad, :bad]
        [:red, :qmark]
      else
        raise 'Ye olde should-not-occur error'
      end

      table = {
        :check => "+",
        :tripple_dot => ".", # "\u2026"
        :cross  => "!",
        :qmark => "?",
      }

      @output.write(table[symbol].colorize(
        :color => :white,
        :background => color
      ))
    end

    def done
      @output.write("\nDone.\n".colorize(:green))
    end
  end
end
