require 'cuffsert/cfarguments'
require 'cuffsert/main'
require 'cuffsert/messages'
require 'cuffsert/presenters'
require 'rx'
require 'rx-rspec'
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

describe 'CuffSert#execute' do
  include_context 'changesets'
  include_context 'metadata'
  include_context 'stack events'
  include_context 'stack states'

  let :cfmock do
    double(:cfclient)
  end

  context 'not finding a matching stack' do
    let(:confirmation) { lambda { |*_| true } }

    before do
      allow(cfmock).to receive(:find_stack_blocking)
        .with(meta)
        .and_return(nil)
    end

    subject do 
      CuffSert.execute(meta, confirmation, :client => cfmock)
    end

    it 'creates it' do
      expect(cfmock).to receive(:create_stack)
        .with(CuffSert.as_create_stack_args(meta))
        .and_return(Rx::Observable.of(r1_done, r2_done))
      expect(subject).to emit_exactly(
        [:create, stack_name],
        r1_done,
        r2_done
      )
    end
    
    context 'given rejection' do
      let(:confirmation) { lambda { |*_| false } }

      it 'takes no action' do
        expect(subject).to emit_exactly(
          [:create, stack_name],
          CuffSert::Abort.new(/.*/)
        )
      end
    end
  end

  context 'finding rolled_back stack' do
    let(:confirm_update) { lambda { |*_| true } }

    let :cfmock do
      mock = double(:cfclient)
      allow(mock).to receive(:find_stack_blocking)
        .and_return(stack_rolled_back)
      mock
    end

    subject { CuffSert.execute(meta, confirm_update, :client => cfmock) }

    context 'given user confirmation' do
      it 'deletes rolledback stack before create' do
        expect(cfmock).to receive(:delete_stack)
          .with(CuffSert.as_delete_stack_args(stack_rolled_back))
          .and_return(Rx::Observable.of(r1_deleted, r2_deleted))
        expect(cfmock).to receive(:create_stack)
          .with(CuffSert.as_create_stack_args(meta))
          .and_return(Rx::Observable.of(r1_done, r2_done))
        expect(subject).to emit_exactly(
          [:recreate, stack_rolled_back],
          r1_deleted,
          r2_deleted,
          r1_done,
          r2_done
        )
      end
    end

    context 'given rejection' do
      let(:confirm_update) { lambda { |*_| false } }

      it 'aborts with neither deletion nor creation' do
        expect(cfmock).not_to receive(:delete_stack)
        expect(cfmock).not_to receive(:create_stack)
        expect(subject).to emit_exactly(
          [:recreate, stack_rolled_back],
          CuffSert::Abort.new(/.*/)
        )
      end
    end
  end

  describe 'update' do
    let(:confirm_update) { lambda { |*_| true } }
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
        expect(cfmock).to receive(:abort_update)
          .and_return(Rx::Observable.empty)
        expect(cfmock).not_to receive(:update_stack)

        expect(subject).to emit_exactly(change_set_failed)
      end
    end

    context 'given rejection' do
      let(:confirm_update) { lambda { |*_| false } }

      it 'does not update' do
        expect(cfmock).to receive(:abort_update)
          .and_return(Rx::Observable.empty)
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

describe 'CuffSert#make_renderer' do
  subject do |example|
    CuffSert.make_renderer(example.metadata)
  end
  
  it 'returns progressbar by default' do
    should be_a(CuffSert::ProgressbarRenderer)
  end
  
  it 'returns json renderer for :json', :output => :json do
    should be_a(CuffSert::JsonRenderer)
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
