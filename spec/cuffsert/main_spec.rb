require 'cuffsert/cfarguments'
require 'cuffsert/main'
require 'cuffsert/messages'
require 'rx'
require 'rx-rspec'
require 'spec_helpers'
require 'stringio'
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
    let(:change_set_changes) { [r1_modify] }
    it { should be(false) }
  end

  context 'with conditional replace' do
    let(:change_set_changes) { [r1_conditional_replace] }
    it { should be(true) }
  end

  context 'with known replacement' do
    let(:change_set_changes) { [r1_replace] }
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
      let(:change_set_changes) { [r1_replace] }
      it { should be(false) }
    end

    context 'with delete' do
      let(:change_set_changes) { [r3_delete] }
      it { should be(false) }
    end
  end
end

describe 'CuffSert#ask_confirmation' do
  let(:output) { StringIO.new }

  subject { CuffSert.ask_confirmation(input, output) }

  context 'given non-tty' do
    let(:input) { StringIO.new }

    it { should be(false) }
    it { expect(output.string).to eq('') }
  end

  # context 'given a tty saying yea' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'Y') }
  #
  #   it { should be(true) }
  #   it { expect(output.string).to match(/continue/) }
  # end
  #
  # context 'given a tty saying nay' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'n') }
  #
  #   it { should be(false) }
  #   it { expect(output.string).to match(/continue/) }
  # end
  #
  # context 'given a tty saying foo' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'f') }
  #
  #   it { should be(false) }
  # end
end

describe 'CuffSert#execute' do
  include_context 'changesets'
  include_context 'metadata'
  include_context 'stack events'
  include_context 'stack states'

  let :cfmock do
    double(:cfclient)
  end

  it 'creates stacks unknown to cf' do
    allow(cfmock).to receive(:find_stack_blocking)
      .with(meta)
      .and_return(nil)
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
    CuffSert.execute(meta, nil, :client => cfmock)
  end

  it 'deletes rolledback stack before create' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_rolled_back)
    expect(cfmock).to receive(:delete_stack)
      .with(CuffSert.as_delete_stack_args(meta))
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
    CuffSert.execute(meta, nil, :client => cfmock)
  end

  describe 'update' do
    let(:confirm_update) { lambda { |_| true } }
    let(:change_set_stream) { Rx::Observable.of(change_set_ready) }

    let :cfmock do
      mock = double(:cfmock)
      allow(mock).to receive(:find_stack_blocking)
        .and_return(stack_complete)
      expect(mock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta))
        .and_return(change_set_stream)
      mock
    end

    subject { CuffSert.execute(meta, confirm_update, :client => cfmock) }

    context 'given confirmation' do
      it 'updates an existing stack' do
        expect(cfmock).to receive(:update_stack)
          .and_return(Rx::Observable.of(r1_done, r2_done))

        expect(subject).to emit_exactly(change_set_ready, r1_done, r2_done)
      end
    end

    context 'when change set failed' do
      let(:change_set_stream) { Rx::Observable.of(change_set_failed) }

      it 'does not update' do
        expect(cfmock).not_to receive(:update_stack)

        expect(subject).to emit_exactly(change_set_failed)
      end
    end

    context 'given rejection' do
      let(:confirm_update) { lambda { |_| false } }

      it 'does not update' do
        expect(cfmock).not_to receive(:update_stack)

        expect(subject).to emit_exactly(change_set_ready, CuffSert::Abort.new(/.*/))
      end
    end
  end

  it 'bails on stack already in progress' do
    allow(cfmock).to receive(:find_stack_blocking)
      .and_return(stack_in_progress)
    expect(
      CuffSert.execute(meta, nil, :client => cfmock)
    ).to emit_exactly(CuffSert::Abort.new(/in progress/))
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
