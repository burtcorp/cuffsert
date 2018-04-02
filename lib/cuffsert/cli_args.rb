require 'optparse'
require 'cuffsert/version'

module CuffSert
  STACKNAME_RE = /^[A-Za-z0-9_-]+$/

  def self.parse_cli_args(argv)
    args = {
      :output => :progressbar,
      :verbosity => 1,
      :force_replace => false,
      :op_mode => nil,
      :overrides => {
        :parameters => {},
        :tags => {},
      }
    }
    parser = OptionParser.new do |opts|
      opts.banner = "Upsert a CloudFormation template, reading creation options and metadata from a yaml file. Currently, parameter values, stack name and stack tags are read from metadata file. Version #{CuffSert::VERSION}."
      opts.separator('')
      opts.separator('Usage: cuffsert --selector production/us stack.json')
      opts.on('--metadata path', '-m path', 'Yaml file to read stack metadata from') do |path|
        path = '/dev/stdin' if path == '-'
        unless File.exist?(path)
          raise "--metadata #{path} does not exist"
        end
        args[:metadata] = path
      end

      opts.on('--selector selector', '-s selector', 'Dash or slash-separated variant names used to navigate the metadata') do |selector|
        args[:selector] = selector.split(/[-,\/]/)
      end

      opts.on('--name stackname', '-n name', 'Alternative stackname (default is to construct the name from the selector)') do |stackname|
        unless stackname =~ STACKNAME_RE
          raise "--name #{stackname} is expected to be #{STACKNAME_RE.inspect}"
        end
        args[:overrides][:stackname] = stackname
      end

      opts.on('--parameter k=v', '-p k=v', 'Set the value of a particular parameter, overriding any file metadata') do |kv|
        key, val = kv.split(/=/, 2)
        if val.nil?
          raise "--parameter #{kv} should be key=value"
        end
        if args[:overrides][:parameters].include?(key)
          raise "cli args include duplicate parameter #{key}"
        end
        args[:overrides][:parameters][key] = val
      end

      opts.on('--tag k=v', '-t k=v', 'Set a stack tag, overriding any file metadata') do |kv|
        key, val = kv.split(/=/, 2)
        if val.nil?
          raise "--tag #{kv} should be key=value"
        end
        if args[:overrides][:tags].include?(key)
          raise "cli args include duplicate tag #{key}"
        end
        args[:overrides][:tags][key] = val
      end

      opts.on('--s3-upload-prefix=prefix', 'Templates > 51200 bytes are uploaded here. Format: s3://bucket-name/[pre/fix]') do |prefix|
        unless prefix.start_with?('s3://')
          raise "Upload prefix #{prefix} must start with s3://"
        end
        args[:s3_upload_prefix] = prefix
      end

      opts.on('--json', 'Output events in JSON, no progressbar, colors') do
        args[:output] = :json
      end

      opts.on('--verbose', '-v', 'More detailed output. Once will print all stack events, twice will print debug info') do
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

      opts.on('--help', '-h', 'Produce this message') do
        abort(opts.to_s)
      end
    end

    if argv.empty?
      abort(parser.to_s)
    else
      args[:stack_path] = parser.parse(argv)
      args
    end
  end
  
  def self.validate_cli_args(cli_args)
    errors = []
    if cli_args[:stack_path].nil? || cli_args[:stack_path].size != 1
      errors << 'Requires exactly one template'
    end

    if cli_args[:metadata].nil? && cli_args[:overrides][:stackname].nil?
      errors << 'Without --metadata, you must supply --name to identify stack to update'
    end
    
    if cli_args[:selector] && cli_args[:metadata].nil?
      errors << 'You cannot use --selector without --metadata'
    end
    
    raise errors.join(', ') unless errors.empty?
  end
end
