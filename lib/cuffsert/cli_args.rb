require 'optparse'
require 'cuff/common_cli_args'

module CuffSert
  def self.parse_cli_args(argv)
    args = Cuff.default_args.merge!(
      :output => :progressbar,
      :verbosity => 1,
      :force_replace => false,
      :op_mode => nil,
      :overrides => {
        :parameters => {},
        :tags => {},
      }
    )

    parser = OptionParser.new do |opts|
      opts.banner = 'Upsert a CloudFormation template, reading creation options and metadata from a yaml file. Currently, parameter values, stack name and stack tags are read from metadata file.'
      opts.separator('')
      opts.separator('Usage: cuffsert --selector production/us stack.json')
      Cuff.apply_common_cli_args(args, opts)

      opts.on('--json', 'Output events in JSON, no progressbar, colors') do
        args[:output] = :json
      end

      opts.on('--verbose', '-v', 'More detailed output. Once will print all stack evwnts, twice will print debug info') do
        args[:verbosity] += 1
      end

      opts.on('--quiet', '-q', 'Output only fatal errors') do
        args[:verbosity] = 0
      end

      opts.on('--replace', 'Re-create the stack if it already exist') do
        args[:force_replace] = true
      end

      opts.on('--yes', '-y', 'Don\'t ask to replace and delete stack resources') do
        raise 'You cannot do --yes and --dry-run at the same time' if args[:op_mode]
        args[:op_mode] = :dangerous_ok
      end

      opts.on('--dry-run', 'Describe what would be done') do
        raise 'You cannot do --yes and --dry-run at the same time' if args[:op_mode]
        args[:op_mode] = :dry_run
      end
    end

    args[:stack_path] = parser.parse(argv)
    args
  end
end
