require 'cuffsert/cfarguments'
require 'cuffsert/main'
require 'spec_helpers'
require 'tempfile'

describe 'CuffSert#validate_and_urlify' do
  let(:s3url) { 's3://ze-bucket/some/url' }
  let(:httpurl) { 'http://some.host/some/file' }

  it 'urlifies and normalizes files' do
    stack = Tempfile.new('stack')
    path = Dir.tmpdir + '/..' + stack.path
    result = CuffSert.validate_and_urlify(path)
    expect(result).to eq(URI.parse("file://#{stack.path}"))
  end

  it 'respects s3 urls' do
    expect(CuffSert.validate_and_urlify(s3url)).to eq(URI.parse(s3url))
  end

  it 'borks on non-existent local files' do
    expect {
      CuffSert.validate_and_urlify('/no/such/file')
    }.to raise_error(/local.*not exist/i)
  end

  it 'borks on unkown schemas' do
    expect {
      CuffSert.validate_and_urlify(httpurl)
    }.to raise_error(/.*http.*not supported/)
  end
end

describe 'CuffSert#build_metadata' do
  include_context 'yaml configs'

  let :cli_args do
    args = {
      :metadata_path => config_file.path,
      :selector => ['level1_a'],
      :overrides => {
        :stackname => 'customname',
        :tags => {'another' => 'tag'}
      },
    }
  end

  subject do
    CuffSert.build_meta(cli_args)
  end

  it 'reads metadata file and allows overrides' do
    expect(subject.stackname).to eq('customname')
    expect(subject.tags).to include(
      'tlevel' => 'level1_a',
      'another' => 'tag'
    )
  end
end

describe 'CuffSert#execute' do
  include_context 'stack states'
  include_context 'metadata'

  let :cfmock do
    double(:cfclient)
  end

  it 'creates stacks unknown to cf' do
    allow(cfmock).to receive(:find_stack_blocking)
      .with(meta)
      .and_return(nil)
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
    CuffSert.execute(meta, :client => cfmock)
  end

  it 'deletes rolledback stack before create' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_rolled_back)
    expect(cfmock).to receive(:delete_stack)
      .with(CuffSert.as_delete_stack_args(meta))
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
    CuffSert.execute(meta, :client => cfmock)
  end

  it 'updates an existing stack' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_complete)
    expect(cfmock).to receive(:update_stack)
      .with(CuffSert.as_update_stack_args(meta))
    CuffSert.execute(meta, :client => cfmock)
  end

  it 'bails on stack already in progress' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_in_progress)
    expect {
      CuffSert.execute(meta, :client => cfmock)
    }.to raise_error(/in progress/)
  end
end
