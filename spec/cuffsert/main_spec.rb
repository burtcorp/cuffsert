require 'cuffsert/cfarguments'
require 'cuffsert/main'
require 'rx'
require 'spec_helpers'
require 'tempfile'

describe 'CuffSert#validate_and_urlify' do
  let(:s3url) { 's3://ze-bucket/some/url' }
  let(:httpurl) { 'http://some.host/some/file' }

  it 'urlifies and normalizes files' do
    stack = Tempfile.new('stack')
    path = '/..' + stack.path
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

describe 'CuffSert#need_confirmation' do
  include_context 'metadata'
  include_context 'changesets'

  let :local_meta do
    meta.dangerous_ok = false
    meta
  end

  subject do
    CuffSert.need_confirmation(local_meta, change_set_ready)
  end

  context 'with adds' do
    let(:change_set_changes) { [r2_add] }
    it { should be(false) }
  end

  context 'with non-replace modify' do
    let(:change_set_changes) { [r1_modify.merge(:replacement => 'False')] }
    it { should be(false) }
  end

  context 'with conditional replace' do
    let(:change_set_changes) { [r1_modify.merge(:replacement => 'Conditional')] }
    it { should be(true) }
  end

  context 'with known replacement' do
    let(:change_set_changes) { [r1_modify.merge(:replacement => 'True')] }
    it { should be(true) }
  end

  context 'with delete' do
    let(:change_set_changes) { [r3_delete] }
    it { should be(true) }
  end

  context 'given dangerous_ok' do
    let :local_meta do
      meta.dangerous_ok = true
      meta
    end

    context 'with known replacement' do
      let(:change_set_changes) { [r1_modify.merge(:replacement => 'True')] }
      it { should be(false) }
    end

    context 'with delete' do
      let(:change_set_changes) { [r3_delete] }
      it { should be(false) }
    end
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

describe 'CuffSert#main' do
  include_context 'yaml configs'
  include_context 'templates'

  it 'works' do
    expect(CuffSert).to receive(:execute)
      .and_return(Rx::Observable.from_array([]))
    CuffSert.run(['--metadata', config_file.path, '--selector', 'level1_a', template_body.path])
  end
end
