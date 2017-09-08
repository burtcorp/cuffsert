require 'cuffsert/cli_args'

def have_overrides(overrides)
  include(:overrides => include(overrides))
end

describe 'CuffSert#parse_cli_args' do
  metadata = Tempfile.new('metadata')
  stack = Tempfile.new('stack')

  subject do |example|
    argv = example.metadata[:argv] || example.metadata[:description_args][0]
    CuffSert.parse_cli_args(argv)
  end

  context 'defaulsts' do
    it { should include(:verbosity => 1) }
    it { should include(:output => :progressbar) }
    it { should include(:force_replace => false) }
  end

  it ['--metadata',  metadata.path] { should include(:metadata => metadata.path) }
  it ['--metadata', '-'] { should include(:metadata => '/dev/stdin') }
  it ['--selector', 'foo/bar/baz'] { should include(:selector => ['foo', 'bar', 'baz']) }
  it ['--tag=foo=bar'] { should have_overrides(:tags => {'foo' => 'bar'}) }
  it ['--name=foo'] { should have_overrides(:stackname => 'foo') }
  it ['--parameter', 'foo=bar'] { should have_overrides(:parameters => {'foo' => 'bar'}) }
  it ['--json'] { should include(:output => :json) }
  it ['--verbose'] { should include(:verbosity => 2) }
  it ['-v', '-v'] { should include(:verbosity => 3) }
  it ['--quiet'] { should include(:verbosity => 0) }
  it ['--replace'] { should include(:force_replace => true) }
  it ['--yes'] { should include(:op_mode => :dangerous_ok) }
  it ['--dry-run'] { should include(:op_mode => :dry_run) }

  it 'stack argument as array beacuse future', :argv => [stack.path] do
    should include(:stack_path => [stack.path])
  end

  it 'rejects unparseable tag', :argv => ['-t', 'asdf'] do
    expect { subject }.to raise_error(/--tag.*asdf/)
  end

  it 'rejects duplicate tag', :argv => ['-t', 'foo=bar', '-t', 'foo=baz'] do
    expect { subject }.to raise_error(/duplicate.*foo/)
  end

  it 'rejects unparseable parameter', :argv => ['-p', 'asdf']  do
    expect { subject }.to raise_error(/--parameter.*asdf/)
  end

  it 'rejects duplicate parameter', :argv => ['-p', 'foo=bar', '-p', 'foo=baz'] do
    expect { subject }.to raise_error(/duplicate.*foo/)
  end

  it 'rejects bad stackname', :argv => ['-n', '*foo'] do
    expect { subject }.to raise_error(/--name.*\*foo/)
  end

  it 'rejects --yes --dry-run', :argv => ['--yes', '--dry-run'] do
    expect { subject }.to raise_error(/--yes and --dry-run/)
  end

  context '--help exit code' do
    original_stderr = $stderr
    before { $stderr = File.open(File::NULL, "w") }
    after { $stderr = original_stderr }

    subject do
      begin
        CuffSert.parse_cli_args(['-h'])
      rescue SystemExit => e
        e.status
      end
    end

    it { should eq(1) }
  end

  it '--help prints usage' do
    expect do
      begin
        CuffSert.parse_cli_args(['-h'])
      rescue SystemExit
      end
    end.to output(/Usage:/).to_stderr
  end
end
