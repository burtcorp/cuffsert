require 'cuffsert/main'
require 'cuffsert/messages'
require 'cuffsert/presenters'
require 'rx'
require 'rx-rspec'
require 'spec_helpers'

describe 'CuffSert#determine_action' do
  include_context 'changesets'
  include_context 'metadata'
  include_context 'stack events'
  include_context 'stack states'

  let(:confirm_update) { lambda { |*_| true } }
  let(:force_replace) { false }

  let :cfmock do
    double(:cfclient)
  end

  before do
    allow(cfmock).to receive(:find_stack_blocking)
      .with(meta)
      .and_return(stack)
  end

  subject do
    CuffSert.determine_action(meta, :force_replace => force_replace, :cfclient => cfmock) { |_| }
  end

  shared_examples 'looking at the action' do
    it 'gets a cloudformation client' do
      expect(subject.cfclient).to eq(cfmock)
    end
  end

  context 'not finding a matching stack' do
    let(:stack) { nil }

    it 'creates it' do
      expect(subject).to be_a(CuffSert::CreateStackAction)
    end

    include_examples 'looking at the action'
  end

  context 'finding rolled-back stack' do
    let(:stack) { stack_rolled_back }

    it 'recreates the stack' do
      expect(subject).to be_a(CuffSert::RecreateStackAction)
    end

    include_examples 'looking at the action'
  end

  context 'finding a completed stack but is explicitly asked to replace it' do
    let(:force_replace) { true }
    let(:stack) { stack_complete }

    it 'recreates the stack' do
      expect(subject).to be_a(CuffSert::RecreateStackAction)
    end

    include_examples 'looking at the action'
  end

  describe 'finding a completed stack' do
    let(:change_set_stream) { Rx::Observable.of(change_set_ready) }
    let(:stack) { stack_complete }

    it 'updates the stack' do
      expect(subject).to be_a(CuffSert::UpdateStackAction)
    end

    include_examples 'looking at the action'
  end

  context 'when a stack operation is already in progress' do
    let(:stack) { stack_in_progress }

    it 'it aborts' do
      expect(subject).to be_a(CuffSert::Abort)
    end
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

  let(:cli_args) do
    ['--metadata', config_file.path, '--selector', 'level1_a', template_body.path]
  end

  let(:action) do
    double(:action).tap do |action|
      allow(action).to receive(:as_observable).and_return(Rx::Observable.from([]))
      allow(action).to receive(:confirmation=)
      allow(action).to receive(:s3client=)
    end
  end

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(double(:s3))
    expect(CuffSert).to receive(:determine_action).and_yield(action).and_return(action)
  end

  it 'works' do
    CuffSert.run(cli_args)
    expect(action).to have_received(:confirmation=)
    expect(action).not_to have_received(:s3client=)
  end

  context 'given --s3-upload-prefix' do
    let(:cli_args) { super() + ['--s3-upload-prefix', 's3://some-bucket'] }

    it 'assigns an S3 client' do
      CuffSert.run(cli_args)
      expect(action).to have_received(:s3client=)
    end
  end
end
