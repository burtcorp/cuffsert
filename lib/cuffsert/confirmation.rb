require 'termios'

module CuffSert
  def self.need_confirmation(meta, action, desc)
    return false if meta.op_mode == :dangerous_ok
    case action
    when :create
      false
    when :update
      change_set = desc
      change_set[:changes].any? do |change|
        rc = change[:resource_change]
        rc[:action] == 'Remove' || (
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
  
  def self.confirmation(meta, action, change_set)
    return false if meta.op_mode == :dry_run
    return true unless CuffSert.need_confirmation(meta, action, change_set)
    return CuffSert.ask_confirmation(STDIN, STDOUT)
  end
end