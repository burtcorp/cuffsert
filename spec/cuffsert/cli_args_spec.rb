require 'cuffsert/cli_args'

describe 'CuffSert#parse_cli_args' do
  it 'accepts --metadata' do
    file = Tempfile.new('metadata')
    result = CuffSert.parse_cli_args(['--metadata',  file.path])
    expect(result).to include(:metadata => file.path)
  end

  it 'accepts --metadata=-' do
    file = Tempfile.new('stack')
    result = CuffSert.parse_cli_args(['--metadata', '-', file.path])
    expect(result).to include(:metadata => '/dev/stdin')
  end

  it 'accepts --selector' do
    result = CuffSert.parse_cli_args(['-s', 'foo/bar/baz'])
    expect(result).to include(:selector => ['foo', 'bar', 'baz'])
  end

  it 'accepts --tag' do
    result = CuffSert.parse_cli_args(['--tag=foo=bar'])[:overrides]
    expect(result).to include(:tags => {'foo' => 'bar'})
  end

  it 'throws meaningfully on unparseable tag' do
    expect {
      CuffSert.parse_cli_args(['-t', 'asdf'])
    }.to raise_error(/--tag.*asdf/)
  end

  it 'throws meaningfully on duplicate tag' do
    expect {
      CuffSert.parse_cli_args(['-t', 'foo=bar', '-t', 'foo=baz'])
    }.to raise_error(/duplicate.*foo/)
  end

  it 'accepts --parameter' do
    result = CuffSert.parse_cli_args(['-p' 'foo=bar'])[:overrides]
    expect(result).to include(:parameters => {'foo' => 'bar'})
  end

  it 'throws meaningfully on unparseable parameter' do
    expect {
      CuffSert.parse_cli_args(['-p', 'asdf'])
    }.to raise_error(/--parameter.*asdf/)
  end

  it 'throws meaningfully on duplicate parameter' do
    expect {
      CuffSert.parse_cli_args(['-p', 'foo=bar', '-p', 'foo=baz'])
    }.to raise_error(/duplicate.*foo/)
  end

  it 'accepts --name' do
    result = CuffSert.parse_cli_args(['--name=foo'])[:overrides]
    expect(result).to include(:stackname => 'foo')
  end

  it 'throws meaningfully on bad stackname' do
    expect {
      CuffSert.parse_cli_args(['-n', '*foo'])
    }.to raise_error(/--name.*\*foo/)
  end

  it 'stack argument as array beacuse future' do
    file = Tempfile.new('stack')
    result = CuffSert.parse_cli_args([file.path])
    expect(result).to include(:stack_path => [file.path])
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
