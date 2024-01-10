require 'cuffsert/cli_args'
require 'tempfile'

def have_overrides(overrides)
  include(:overrides => include(overrides))
end

describe 'CuffSert#parse_cli_args' do
  metadata = Tempfile.new('metadata')
  stack = Tempfile.new('stack')

  subject do |example|
    dummy_nonempty_argv = ['-y']
    argv = example.metadata[:argv] || example.metadata[:description_args][0] || dummy_nonempty_argv
    CuffSert.parse_cli_args(argv)
  end

  context 'defaults' do
    it { should include(:verbosity => 1) }
    it { should include(:output => :progressbar) }
    it { should include(:force_replace => false) }
  end

  it(['--metadata',  metadata.path]) { should include(:metadata => metadata.path) }
  it(['--metadata', '-']) { should include(:metadata => '/dev/stdin') }
  it(['--selector', 'foo/bar/baz']) { should include(:selector => ['foo', 'bar', 'baz']) }
  it(['--tag=foo=bar']) { should have_overrides(:tags => {'foo' => 'bar'}) }
  it(['--name=foo']) { should have_overrides(:stackname => 'foo') }
  it(['--parameter', 'foo=bar']) { should have_overrides(:parameters => {'foo' => 'bar'}) }
  it(['--region', 'eu-west-1']) { should include(:aws_region => 'eu-west-1') }
  it(['--s3-upload-prefix', 's3://foo/bar']) { should include(:s3_upload_prefix => 's3://foo/bar')}
  it(['--json']) { should include(:output => :json) }
  it(['--verbose']) { should include(:verbosity => 2) }
  it(['-v', '-v']) { should include(:verbosity => 3) }
  it(['--quiet']) { should include(:verbosity => 0) }
  it(['--replace']) { should include(:force_replace => true) }
  it(['--ask']) { should include(:op_mode => :always_ask) }
  it(['--yes']) { should include(:op_mode => :dangerous_ok) }
  it(['--dry-run']) { should include(:op_mode => :dry_run) }

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

  it 'rejects --ask --dry-run', :argv => ['--ask', '--dry-run'] do
    expect { subject }.to raise_error(/--yes.* --dry-run/)
  end

  it 'rejects --yes --dry-run', :argv => ['--yes', '--dry-run'] do
    expect { subject }.to raise_error(/--ask.* --dry-run/)
  end

  it 'rejects s3 upload prefix not starting with s3:', :argv => ['--s3-upload-prefix', 'foobar'] do
    expect { subject }.to raise_error(/foobar.*s3:/)
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

  it 'no args prints usage' do
    expect do
      begin
        CuffSert.parse_cli_args([])
      rescue SystemExit
      end
    end.to output(/Usage:/).to_stderr
  end
end

describe 'CuffSert#validate_cli_args' do
  let(:cli_args) { {:overrides => {}} }

  subject { CuffSert.validate_cli_args(cli_args) }

  context 'when no --metadata and no --name' do
    it { expect { subject }.to raise_error(/supply --name/i) }
  end
  
  context 'when no --metadata and --selector' do
    let(:cli_args) { super().merge({:selector => '/foo'}) }
    it { expect { subject }.to raise_error(/cannot use --selector.*without --metadata/i) }
  end

  context 'when no stack path' do
    let :cli_args do
      super().tap do |args|
        args[:overrides][:stackname] = 'some-stack'
        args[:stack_path] = []
      end
    end

    it { expect { subject }.not_to raise_error }
  end

  context 'with multiple stack paths' do
    let(:cli_args) { super().merge({:stack_path => ['foo', 'bar']}) }
    it { expect { subject }.to raise_error(/one.*template/i) }
  end
end
