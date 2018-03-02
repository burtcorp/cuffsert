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

  context 'not finding a matching stack' do
    let(:stack) { nil }

    it 'creates it' do
      expect(subject).to be_a(CuffSert::CreateStackAction)
    end
  end

  context 'finding rolled-back stack' do
    let(:stack) { stack_rolled_back }

    it 'recreates the stack' do
      expect(subject).to be_a(CuffSert::RecreateStackAction)
    end
  end

  context 'finding a completed stack but is explicitly asked to replace it' do
    let(:force_replace) { true }
    let(:stack) { stack_complete }

    it 'recreates the stack' do
      expect(subject).to be_a(CuffSert::RecreateStackAction)
    end
  end

  describe 'finding a completed stack' do
    let(:change_set_stream) { Rx::Observable.of(change_set_ready) }
    let(:stack) { stack_complete }

    it 'updates the stack' do
      expect(subject).to be_a(CuffSert::UpdateStackAction)
    end
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

  let(:action) do
    double(:action).tap do |action|
      allow(action).to receive(:as_observable).and_return(Rx::Observable.from([]))
    end
  end

  it 'works' do
    expect(CuffSert).to receive(:determine_action).and_return(action)
    CuffSert.run(['--metadata', config_file.path, '--selector', 'level1_a', template_body.path])
  end
end
