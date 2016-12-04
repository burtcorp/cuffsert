require 'spec_helpers'
require 'tempfile'

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