require 'cuffbase'
require 'optparse'

module CuffUp
  def self.parse_cli_args(argv)
    args = {
      :output => '/dev/stdout'
    }
    parser = OptionParser.new do |opts|
      opts.banner = 'Output CuffSert-formatted metadata defaults based on a stack template.'
      opts.separator('')
      opts.separator('Usage: cuffup <template.json>')
      opts.on('--output metadata', '-o metadata', 'File to write metadata file to; defaults to stdout') do |f|
        args[:output] = f
      end

      opts.on('--selector selector', '-s selector', 'Set as sufflx in the generated output') do |selector|
        args[:selector] = selector.split(/[-,\/]/)
      end
    end

    args[:template] = parser.parse(argv)
    args
  end

  def self.parameters(io)
    CuffBase.defaults_from_template(io)
    .map {|k, v| {'Name' => k, 'Value' => v} }
  end

  def self.dump(args, input, output)
    result = {
      'Format' => 'v1',
    }
    result['Parameters'] = input if input.size > 0
    result['Suffix'] = args[:selector].join('-') if args.include?(:selector)
    YAML.dump(result, output)
  end

  def self.run(args, input, output)
    self.dump(args, self.parameters(input), output)
  end
end
