require 'colorize'
require 'cuffsert/cfstates'
require 'cuffsert/messages'
require 'hashdiff'

module CuffSert
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
        sprintf("%s[%s] %-10s %s\n%s",
          rc[:logical_resource_id],
          rc[:resource_type],
          action_color(action(rc)),
          scope_desc(rc),
          change_details(rc)
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
      @template_changes = Hashdiff.best_diff(current, pending, array_path: true)
      @template_changes.each {|c| p c} if ENV['CUFFSERT_EXPERIMENTAL']
      present_changes(extract_changes(@template_changes, 'Conditions'), 'Conditions') unless @verbosity < 1
      present_changes(extract_changes(@template_changes, 'Parameters'), 'Parameters') unless @verbosity < 1
      present_changes(extract_changes(@template_changes, 'Mappings'), 'Mappings') unless @verbosity < 1
      present_changes(extract_changes(@template_changes, 'Outputs'), 'Outputs') unless @verbosity < 1
    end

    def report(event)
      @output.write(event.message.colorize(:white) + "\n") unless @verbosity < 2
    end

    def abort(event)
      @error.write("\n" + event.message.colorize(:red) + "\n") unless @verbosity < 1
    end

    def done(event)
      @output.write(event.message.colorize(:green) + "\n") unless @verbosity < 1
    end

    private

    def change_details(rc)
      (rc[:details] || []).flat_map do |detail|
        target_path = case detail[:target][:attribute]
        when 'Properties'
          [rc[:logical_resource_id], detail[:target][:attribute], detail[:target][:name]]
        when 'Tags'
          [rc[:logical_resource_id], 'Properties', detail[:target][:attribute]]
        else
          nil
        end
        extract_changes(@template_changes, 'Resources', *target_path)
      end
      .map do |(ch, path, l, r)|
        format_change(ch, path[3..-1], l, r)
      end
      .join
    end

    def extract_changes(changes, type, *target_path)
      changes
        .select {|(_, path, _)| path[0..target_path.size] == [type, *target_path] }
        .map {|(ch, path, *rest)| [ch, path, *rest] }
    end

    def present_changes(changes, type)
      return unless changes.size > 0
      @output.write("#{type}:\n")
      changes.each do |(ch, path, l, r)|
        @output.write(format_change(ch, path, l, r))
      end
    end

    def format_change(ch, path, l, r = nil)
      sprintf("%s %s: %s\n",
        change_color(ch),
        path.join('/'),
        format_changed_value(ch, l, r),
      )
    end

    def change_color(ch)
      ch.colorize(
        case ch
        when '-' then :red
        when '+' then :green
        when '~' then :yellow
        else :white
        end
      )
    end

    def format_changed_value(ch, l, r)
      if ch == '~'
        if l.is_a?(String) and r.is_a?(String)
          l_lines = l.each_line(chomp: true).to_a
          r_lines = r.each_line(chomp: true).to_a
          if l_lines.size > 1 or r_lines.size > 1
            differ = DiffWithContext.new(color: true)
            return sprintf(
              "String diff:\n%s",
              differ.generate_for(l_lines, r_lines)
            )
          end
        end
        "#{l} -> #{r}"
      else
        l
      end
    end

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

  class DiffWithContext
    def initialize(ctx_size: 3, color: false)
      @ctx_size = ctx_size
      @color = color
    end

    def generate_for(left, right)
      buf = StringIO.new
      lineno_size = left.size.to_s.size
      diff = Hashdiff.best_diff(left, right, array_path: true)
      with_context(diff, left) do |ch, lineno, line|
        if ch == '!'
          change = "...\n"
        elsif ch == '-'
          change = sprintf("%s %#{lineno_size}d %s\n", ch, lineno, line)
          change = change.colorize(:red) if @color
        elsif ch == '+'
          change = sprintf("%s #{' ' * lineno_size} %s\n", ch, line)
          change = change.colorize(:green) if @color
        else
          change = sprintf("  %#{lineno_size}d %s\n", lineno, line)
        end
        buf << change
      end
      buf.string
    end

    private

    def with_context(diff, left)
      current_lineno = 0
      diff.chain([[nil, [left.size], nil]]).each_cons(2) do |(ch, path_this, line), (_, path_next, _)|
        lineno_this = path_this[0]
        lineno_next = path_next[0]
        # skip forward
        if lineno_this - @ctx_size > current_lineno
          if current_lineno > 0
            yield '!', nil, nil
          end
          current_lineno = lineno_this - @ctx_size
        end
        # emit context before
        left[current_lineno...lineno_this].each do |c|
          current_lineno += 1
          yield nil, current_lineno, c
        end
        # emit change
        if ch != '+'
          current_lineno += 1
        end
        yield ch, current_lineno, line
        # emit context after
        last_ctx_lineno = [current_lineno + @ctx_size, lineno_next].min
        left[current_lineno...last_ctx_lineno].each do |c|
          current_lineno += 1
          yield nil, current_lineno, c
        end
      end
    end
  end
end
