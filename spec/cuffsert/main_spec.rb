require 'spec_helpers'
require 'tempfile'

describe 'CuffSert#validate_and_urlify' do
  let(:s3url) { 's3://ze-bucket/some/url' }
  let(:httpurl) { 'http://some.host/some/file' }
  
  it 'urlifies and normalizes files' do
    stack = Tempfile.new('stack')
    path = Dir.tmpdir + '/..' + stack.path
    result = CuffSert.validate_and_urlify(path)
    expect(result).to eq("file:///#{stack.path}")
  end
  
  it 'respects s3 urls' do
    expect(CuffSert.validate_and_urlify(s3url)).to eq(s3url)
  end
  
  it 'borks on non-existent local files' do
    expect { 
      CuffSert.validate_and_urlify('/no/such/file')
    }.to raise_error(/local.*not exist/)
  end
  
  it 'borks on unkown schemas' do
    expect {
      CuffSert.validate_and_urlize(httpurl)
    }.to raise_error(/unknown.*http/)
  end
end

describe 'CuffSert#build_metadata' do
  subject do
    meta = Tempfile.new('metadata')
    meta.write(config_yaml)
    meta.close
    args = {
      :metadata_path => meta.path,
      :selector => 'level1_a',
      :stackname => 'customname',
      :overrides => {
        :tags => ['another' => 'tag']
      },
    }
    build_meta(args)
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

  let :cfmock do
    double(:cfclient)
  end
  
  it 'creates stacks unknown to cf' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(nil)
    CuffSert.execute(meta, :cfclient => cfmock)
    expect(cfmock).to have_received(:create_stack)
  end
  
  it 'deletes rolledback stack before create' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_rolled_back)
    CuffSert.execute(meta, :cfclient => cfmock)
    expect(cfmock).to have_received(:delete_stack)
    expect(cfmock).to have_received(:create_stack)
  end
  
  it 'updates an existing stack' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_complete)
    CuffSert.execute(meta, :cfclient => cfmock)
    expect(cfmock).to have_received(:update_stack)
  end
  
  it 'bails on stack already in progress' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_in_progress)
    expect {
      CuffSert.execute(meta, :cfclient => cfmock)
    }.to raise_error(/in progress/)
  end
end