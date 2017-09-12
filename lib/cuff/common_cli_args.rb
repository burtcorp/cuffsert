module Cuff
  STACKNAME_RE = /^[A-Za-z0-9_-]+$/

  def self.default_args
    {
      :overrides => {
        :parameters => {},
        :tags => {},
      }
    }
  end

  def self.apply_common_cli_args(args, opts)
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

    opts.on('--name stackname', '-n name', 'Alternative stackname (default is to construct the name from the selector') do |stackname|
      unless stackname =~ STACKNAME_RE
        raise "--name #{stackname} is expected to be #{STACKNAME_RE.inspect}"
      end
      args[:overrides][:stackname] = stackname
    end

    opts.on('--parameter kv', '-p kv', 'Set the value of a particular parameter, overriding any file metadata') do |kv|
      key, val = kv.split(/=/, 2)
      if val.nil?
        raise "--parameter #{kv} should be key=value"
      end
      if args[:overrides][:parameters].include?(key)
        raise "cli args include duplicate parameter #{key}"
      end
      args[:overrides][:parameters][key] = val
    end

    opts.on('--tag kv', '-t kv', 'Set a stack tag, overriding any file metadata') do |kv|
      key, val = kv.split(/=/, 2)
      if val.nil?
        raise "--tag #{kv} should be key=value"
      end
      if args[:overrides][:tags].include?(key)
        raise "cli args include duplicate tag #{key}"
      end
      args[:overrides][:tags][key] = val
    end

    opts.on('--help', '-h', 'Produce this message') do
      abort(opts.to_s)
    end
    opts
  end
end
