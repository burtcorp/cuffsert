require 'cuffsert/messages'
require 'cuffsert/presenters'
require 'rx'
require 'spec_helpers'

describe CuffSert::RendererPresenter do
  include_context 'stack events'

  class RecordingRenderer
    attr_reader :rendered
    def initialize
      @rendered = []
    end

    def event(event, resource)
      @rendered << :error if resource[:states][-1] == :bad
    end

    def clear
      @rendered << :clear
    end

    def resource(resource)
      @rendered << resource[:states]
    end

    def abort(event)
      @rendered << event
    end

    def done
      @rendered << :done
    end
  end

  let(:renderer) { RecordingRenderer.new }
  let(:stream) { Rx::Observable.from(events) }

  before { CuffSert::RendererPresenter.new(stream, renderer) }

  subject { renderer.rendered }

  context 'given successful stack events' do
    let (:events) { [r1_done, r2_progress, r2_done] }

    it 'renders correct status' do
      should eq([
        :clear, [:good],
        :clear, [:good], [:progress],
        :clear, [:good], [:good],
        :done
      ])
    end
  end

  context 'given a rollbacking resource' do
    let (:events) { [r2_progress, r2_failed, r2_rolling_back, r2_deleted] }

    it 'renders correct status' do
      should eq([
        :clear, [:progress],
        :error, :clear, [:bad],
        :clear, [:bad, :progress],
        :clear, [:bad, :good],
        :done
      ])
    end
  end

  context 'given an abort message' do
    let(:events) { [CuffSert::Abort.new('badness'), :done] }

    it { should eq(events) }
  end
end

describe CuffSert::ProgressbarRenderer do
  include_context 'stack events'

  describe '#event' do
    subject do
      output = StringIO.new
      described_class.new(output).event(event, resource)
      output.string
    end

    context 'given an in_progress event' do
      let(:event) { r2_progress }
      let(:resource) { event.to_h.merge!(:states => [:progress]) }
      it { should be_empty }
    end

    context 'given an failed event' do
      let(:event) { r2_failed }
      let(:resource) { event.to_h.merge!(:states => [:bad]) }
      it { should match(/resource2_name/) }
      it { should include('Insufficient permissions') }
    end
  end

  describe '#resource' do
    subject do
      output = StringIO.new
      described_class.new(output).resource(resource)
      output.string
    end

    context 'given bad :states' do
      let(:resource) { r2_progress.to_h.merge({:states => []}) }
      it { expect { subject }.to raise_error(/:states/) }
    end
  end

  describe '#change_set' do
    include_context 'changesets'

    subject do
      output = StringIO.new
      described_class.new(output).change_set(changeset)
      output.string
    end

    context 'given an update changeset' do
      let(:changeset) { change_set_ready }
      let(:change_set_changes) { [r2_add] }

      it { should include('Updating ze-stack') }
      it { should include('resource2_id') }

      context 'with a non-replacing changeset' do
        let(:change_set_changes) { [r1_modify] }

        it { should include('Modify'.colorize(:yellow)) }
      end

      context 'with an unconditional replacement' do
        let(:change_set_changes) { [r1_replace] }

        it { should include('Replace!'.colorize(:red)) }
      end

      context 'with a conditional replacement' do
        let(:change_set_changes) { [r1_conditional_replace] }

        it { should include('Replace?'.colorize(:red)) }
      end

      context 'with two changes' do
        let(:change_set_changes) { [r1_replace, r2_add, r1_conditional_replace] }
        it('sorts according to action') do
          should match(/add.*replace\?.*replace!/im)
        end
      end
    end
  end

  describe '#abort' do
    subject do
      output = StringIO.new
      described_class.new(output).abort(message)
      output.string
    end

    context 'given a simple abort message' do
      let(:message) { CuffSert::Abort.new('badness') }
      it { should include('badness'.colorize(:red)) }
    end
  end
end
