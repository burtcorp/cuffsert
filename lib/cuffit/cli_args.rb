require 'optparse'
require 'cuff/common_cli_args'

module CuffIt
  def self.parse_cli_args(argv)
    args = Cuff.default_args

    parser = OptionParser.new do |opts|
      opts.banner = 'Make sure metadata yml is up to date, creating or updating it as necessary.'
      opts.separator('')
      opts.separator('Usage: cuffit --metadata metadata.yml --selector production/us stack.json')
      Cuff.apply_common_cli_args(args, opts)
    end

    args[:stack_path] = parser.parse(argv)
    args
  end
end
