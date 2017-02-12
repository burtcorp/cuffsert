require 'cuffsert/cfarguments'
require 'cuffsert/cfstates'
require 'cuffsert/cli_args'
require 'cuffsert/messages'
require 'cuffsert/metadata'
require 'cuffsert/presenters'
require 'cuffsert/rxcfclient'
require 'rx'
require 'termios'
require 'uri'

# TODO:
# - Stop using file: that we anyway need to special-case in cfarguments
# - default value for meta.metadata when stack_path is local file
# - selector and metadata are mandatory and need guards accordingly
# - validate_and_urlify belongs in metadata.rb
# - execute should use helpers and not know details of statuses
# - update 'abort' should delete cheangeset and emit the result

module CuffSert
  def self.validate_and_urlify(stack_path)
    if stack_path =~ /^[A-Za-z0-9]+:/
      stack_uri = URI.parse(stack_path)
    else
      normalized = File.expand_path(stack_path)
      unless File.exist?(normalized)
        raise "Local file #{normalized} does not exist"
      end
      stack_uri = URI.join('file:///', normalized)
    end
    unless ['s3', 'file'].include?(stack_uri.scheme)
      raise "Uri #{stack_uri.scheme} is not supported"
    end
    stack_uri
  end

  def self.need_confirmation(meta, action, desc)
    return false if meta.dangerous_ok
    case action
    when :update
      change_set = desc
      change_set[:changes].any? do |change|
        rc = change[:resource_change]
        rc[:action] == 'Delete' || (
          rc[:action] == 'Modify' &&
          ['Always', 'True', 'Conditional'].include?(rc[:replacement])
        )
      end
    when :recreate
      true
    else
      true # safety first
    end
  end

  def self.ask_confirmation(input = STDIN, output = STDOUT)
    return false unless input.isatty
    state = Termios.tcgetattr(input)
    mystate = state.dup
    mystate.c_lflag |= Termios::ISIG
    mystate.c_lflag &= ~Termios::ECHO
    mystate.c_lflag &= ~Termios::ICANON
    output.write 'Continue? [yN] '
    begin
      Termios.tcsetattr(input, Termios::TCSANOW, mystate)
      answer = input.getc.chr.downcase
      output.write("\n")
      answer == 'y'
    rescue Interrupt
      false
    ensure
      Termios.tcsetattr(input, Termios::TCSANOW, state)
    end
  end

  def self.create_stack(client, meta)
    cfargs = CuffSert.as_create_stack_args(meta)
    client.create_stack(cfargs)
  end

  def self.update_stack(client, meta, confirm_update)
    cfargs = CuffSert.as_update_change_set(meta)
    client.prepare_update(cfargs)
      .last
      .flat_map do |change_set|
        Rx::Observable.concat(
          Rx::Observable.of(change_set),
          Rx::Observable.defer {
            if change_set[:status] == 'FAILED'
              Rx::Observable.empty
            elsif confirm_update.call(meta, :update, change_set)
              client.update_stack(change_set[:stack_id], change_set[:change_set_id])
            else
              Abort.new('User abort!').as_observable
            end
          }
        )
      end
  end

  def self.recreate_stack(client, stack, meta, confirm_recreate)
    crt_args = CuffSert.as_create_stack_args(meta)
    del_args = CuffSert.as_delete_stack_args(stack)
    Rx::Observable.concat(
      Rx::Observable.of([:recreate, stack]),
      Rx::Observable.defer do
        if confirm_recreate.call(meta, :recreate, stack)
          Rx::Observable.concat(
            client.delete_stack(del_args),
            client.create_stack(crt_args)
          )
        else
          CuffSert::Abort.new('User abort!').as_observable
        end
      end
    )
  end

  def self.execute(meta, confirm_update, client: RxCFClient.new)
    sources = []
    found = client.find_stack_blocking(meta)

    if found && INPROGRESS_STATES.include?(found[:stack_status])
      sources << Abort.new('Stack operation already in progress').as_observable
    elsif found.nil?
      sources << self.create_stack(client, meta)
    elsif found[:stack_status] == 'ROLLBACK_COMPLETE'
      sources << self.recreate_stack(client, found, meta, confirm_update)
    else
      sources << self.update_stack(client, meta, confirm_update)
    end
    Rx::Observable.concat(*sources)
  end

  def self.run(argv)
    cli_args = CuffSert.parse_cli_args(argv)
    meta = CuffSert.build_meta(cli_args)
    if cli_args[:stack_path].nil? || cli_args[:stack_path].size != 1
      raise 'Requires exactly one stack path'
    end
    stack_path = cli_args[:stack_path][0]
    meta.stack_uri = CuffSert.validate_and_urlify(stack_path)
    events = CuffSert.execute(meta, lambda do |meta, action, change_set|
      !CuffSert.need_confirmation(meta, action, change_set) ||
        CuffSert.ask_confirmation(STDIN, STDOUT)
    end)
    RendererPresenter.new(events, ProgressbarRenderer.new)
  end
end
