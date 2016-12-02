require 'optparse'

# TODO:
# - add usage message
# - selector is required

module CuffSert
  STACKNAME_RE = /^[A-Za-z0-9_-]+$/

  def self.parse_cli_args(argv)
    args = {
      :overrides => {
        :parameters => [],
        :tags => [],
      }
    }
    parser = OptionParser.new do |opts|
      opts.on('--metadata path', '-m path') do |path|
        path = '/dev/stdin' if path == '-'
        unless File.exist?(path)
          raise "--metadata #{path} does not exist"
        end
        args[:metadata] = path
      end

      opts.on('--selector selector', '-s selector') do |selector|
        args[:selector] = selector.split(/[-,\/]/)
      end

      opts.on('--name stackname', '-n name') do |stackname|
        unless stackname =~ STACKNAME_RE
          raise "--name #{stackname} is expected to be #{STACKNAME_RE.inspect}"
        end
        args[:overrides][:stackname] = stackname
      end

      opts.on('--parameter kv', '-p kv') do |kv|
        key, val = kv.split(/=/, 2)
        if val.nil?
          raise "--parameter #{kv} should be key=value"
        end
        args[:overrides][:parameters] << {key => val}
      end

      opts.on('--tag kv', '-t kv') do |kv|
        key, val = kv.split(/=/, 2)
        if val.nil?
          raise "--tag #{kv} should be key=value"
        end
        args[:overrides][:tags] << {key => val}
      end
    end
    args[:stack_path] = parser.parse(argv)
    args
  end
end
