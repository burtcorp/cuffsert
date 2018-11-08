require 'cuffbase'
require 'cuffsert/metadata'
require 'cuffsert/rxcfclient'
require 'optparse'
require 'yaml'

module CuffDown
  def self.parse_cli_args(argv)
    args = {}
    parser = OptionParser.new do |opts|
      opts.banner = 'Output CuffSert-formatted metadata from an existing stack.'
      opts.separator('')
      opts.separator('Usage: cuffdown <stack-name>')
      CuffBase.shared_cli_args(opts, args)
    end
    stackname, _ = parser.parse(argv)
    args[:stackname] = stackname
    args
  end

  def self.parameters(stack)
    (stack[:parameters] || []).map do |param|
      {
        'Name' => param[:parameter_key],
        'Value' => param[:parameter_value],
      }
    end
  end

  def self.tags(stack)
    (stack[:tags] || []).map do |param|
      {
        'Name' => param[:key],
        'Value' => param[:value],
      }
    end
  end

  def self.dump(name, params, tags, output)
    result = {
      'Format' => 'v1',
      'Suffix' => name,
      'Parameters' => params,
      'Tags' => tags,
    }
    YAML.dump(result, output)
  end

  def self.run(argv, output)
    cli_args = self.parse_cli_args(argv)
    meta = CuffSert::StackConfig.new
    meta.stackname = cli_args[:stackname]
    client = CuffSert::RxCFClient.new(cli_args[:aws_region])
    stack = client.find_stack_blocking(meta)
    unless stack
      STDERR.puts "No such stack #{meta.stackname}"
      exit(1)
    end
    stack = stack.to_h
    self.dump(
      stack[:stack_name],
      self.parameters(stack),
      self.tags(stack),
      output
    )
  end
end
