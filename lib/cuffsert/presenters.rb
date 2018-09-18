require 'aws-sdk-cloudformation'
require 'colorize'
require 'cuffsert/cfstates'
require 'cuffsert/messages'
require 'hashdiff'
require 'rx'

# TODO: Animate in-progress states
# - Present the error message in change_set properly - and abort
# - badness goes to stderr
# - change sets should present modification details indented under each entry
#   - property direct modification
#   - properties through parameter change
#   - indirect change through other resource ("causing_entity": "Lb.DNSName")

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
      else
        puts event
      end
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

  class BaseRenderer
    def initialize(output = STDOUT, error = STDERR, options = {})
      @output = output
      @error = error
      @verbosity = options[:verbosity] || 1
    end

    def templates(current, pending) ; end
    def change_set(change_set) ; end
    def event(event, resource) ; end
    def clear ; end
    def resource(resource) ; end
    def report(message) ; end
    def abort(message) ; end
    def done(event) ; end
  end

  class JsonRenderer < BaseRenderer
    def templates(current, pending)
      if @verbosity >= 1
        @output.write(current.to_json)
        @output.write(pending.to_json)
      end
    end

    def change_set(change_set)
      @output.write(change_set.to_h.to_json) unless @verbosity < 1
    end

    def event(event, resource)
      @output.write(event.to_h.to_json) unless @verbosity < 1
    end

    def stack(event, stack)
      @output.write(stack.to_json) unless @verbosity < 1
    end

    def report(event)
      @output.write(event.message + "\n") unless @verbosity < 2
    end

    def abort(event)
      @error.write(event.message + "\n") unless @verbosity < 1
    end
  end

  ACTION_ORDER = ['Add', 'Modify', 'Replace?', 'Replace!', 'Remove']

  class ProgressbarRenderer < BaseRenderer
    def change_set(change_set)
      @output.write(sprintf("Updating stack %s\n", change_set[:stack_name]))
      change_set[:changes].sort do |l, r|
        lr = l[:resource_change]
        rr = r[:resource_change]
        [
          ACTION_ORDER.index(action(lr)),
          lr[:logical_resource_id]
        ] <=> [
          ACTION_ORDER.index(action(rr)),
          rr[:logical_resource_id]
        ]
      end.map do |change|
        rc = change[:resource_change]
        sprintf("%s[%s] %-10s %s\n",
          rc[:logical_resource_id],
          rc[:resource_type],
          action_color(action(rc)),
          scope_desc(rc)
        )
      end.each { |row| @output.write(row) }
    end

    def action(rc)
      if rc[:action] == 'Modify'
        if ['True', 'Always'].include?(rc[:replacement])
          'Replace!'
        elsif ['False', 'Never'].include?(rc[:replacement])
          'Modify'
        elsif rc[:replacement] == 'Conditional'
          'Replace?'
        else
          "#{rc[:action]}/#{rc[:replacement]}"
        end
      else
        rc[:action]
      end
    end

    def action_color(action)
      action.colorize(
        case action
        when 'Add' then :green
        when 'Modify' then :yellow
        else :red
        end
      )
    end

    def scope_desc(rc)
      (rc[:scope] || []).map do |scope|
        case scope
        when 'Properties'
          properties = rc[:details]
            .select { |detail| detail[:target][:attribute] == 'Properties' }
            .map { |detail| detail[:target][:name] }
            .uniq
            .join(", ")
          sprintf("Properties: %s", properties)
        else
          rc[:scope]
        end
      end
      .join("; ")
    end

    def event(event, resource)
      return if @verbosity == 0
      return if resource[:states][-1] != :bad && @verbosity <= 1
      color, _ = interpret_states(resource)
      message = sprintf('%s %s  %s[%s] %s',
        event[:resource_status],
        event[:timestamp].strftime('%H:%M:%S%z'),
        event[:logical_resource_id],
        event[:resource_type].sub(/.*::/, ''),
        event[:resource_status_reason] || ""
      ).colorize(color)
      @output.write("\r#{message}\n")
    end

    def stack(event, stack)
      case event
      when :create
        @output.write("Creating stack #{stack}\n")
      when :recreate
        message = sprintf(
          "Deleting and re-creating stack %s",
          stack[:stack_name]
        )
        @output.write(message.colorize(:red) + "\n")
      else
        puts event, stack
      end
    end

    def clear
      @output.write("\r") unless @verbosity < 1
    end

    def resource(resource)
      return if @verbosity < 1
      color, symbol = interpret_states(resource)
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

    def templates(current, pending)
      @current_template = current
      @pending_template = pending
      @template_changes = HashDiff.best_diff(current, pending, array_path: true)
      @template_changes.each {|c| p c} if ENV['CUFFSERT_EXPERIMENTAL']
    end

    def report(event)
      @output.write(event.message.colorize(:white) + "\n") unless @verbosity < 2
    end

    def abort(event)
      @error.write(event.message.colorize(:red) + "\n") unless @verbosity < 1
    end

    def done(event)
      @output.write(event.message.colorize(:green) + "\n") unless @verbosity < 1
    end

    private

    def interpret_states(resource)
      case resource[:states]
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
        raise "Unexpected :states in #{resource.inspect}"
      end
    end
  end
end
