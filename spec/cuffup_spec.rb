require 'cuffup'

describe 'CuffUp.parse_cli_args' do
  subject do |example|
    argv = example.metadata[:argv] || example.metadata[:description_args][0]
    CuffUp.parse_cli_args(argv)
  end

  it([]) { should include(:output => '/dev/stdout') }

  it(['--selector', 'foo']) { should include(:selector => ['foo']) }
  it(['--output', '/some/file']) { should include(:output => '/some/file') }
end

describe 'CuffUp.run' do
  include_context 'templates'

  let(:metadata) { Tempfile.new(['metadata', '.yml']) }
  let(:parameters) { {'from_template' => {'Default' => 'ze-default'}} }
  let(:template_json) { JSON.dump({'Parameters' => parameters}) }

  subject do
    CuffUp.run({}, template_body, metadata)
    metadata.rewind
    YAML.load(metadata)
  end

  it { should include('Parameters' => [{'Name' => 'from_template', 'Value' => 'ze-default'}]) }
end
