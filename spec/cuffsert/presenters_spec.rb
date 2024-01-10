require 'cuffsert/messages'
require 'cuffsert/presenters'
require 'rx'
require 'spec_helpers'

describe CuffSert::RendererPresenter do
  include_context 'stack states'
  include_context 'stack events'

  class RecordingRenderer
    attr_reader :rendered
    def initialize
      @rendered = []
    end

    def templates(current, pending)
      @rendered << [:templates, current, pending]
    end

    def event(event, resource)
      @rendered << :error if resource[:states][-1] == :bad
    end

    def stack(event, stack)
      @rendered << [event, stack]
    end

    def clear
      @rendered << :clear
    end

    def resource(resource)
      @rendered << resource[:states]
    end

    def report(event)
      @rendered << event
    end

    def abort(event)
      @rendered << event
    end

    def done(event)
      @rendered << :done
    end
  end

  let(:renderer) { RecordingRenderer.new }
  let(:stream) { Rx::Observable.from(events) }

  subject do
    CuffSert::RendererPresenter.new(stream, renderer)
    renderer.rendered
  end

  context 'given the involved templates' do
    let(:events) { [CuffSert::Templates.new([:current, :pending])] }

    it { should eq([[:templates, :current, :pending]]) }
  end

  context 'given successful stack events' do
    let (:events) { [r1_done, r2_progress, r2_done] }

    it 'renders correct status' do
      should eq([
        :clear, [:good],
        :clear, [:good], [:progress],
        :clear, [:good], [:good],
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
      ])
    end
  end

  context 'given a well-behaved resource with cleanup in a failed update' do
    let(:events) { [r2_updated, r2_updated, r2_updating, r2_updated] }

    it 'reverts second state position to :progress' do
      should eq([
        :clear, [:good],
        :clear, [:good, :good],
        :clear, [:good, :progress],
        :clear, [:good, :good],
      ])
    end
  end

  context 'given recreate of a rolled-back stack' do
    let (:events) do
      [[:recreate, stack_rolled_back], r1_done, s1_deleted, r1_done, s1_done]
    end

    it 'pass it to renderer' do
      should eq([
        [:recreate, stack_rolled_back],
        :clear, [:good],
        :clear, [:good], [:good],
        :clear, [:good],
        :clear, [:good], [:good],
      ])
    end
  end

  context 'given a report message' do
    let(:events) { [CuffSert::Report.new('goodness')] }

    it { should eq(events) }
  end

  context 'given an abort message' do
    let(:events) { [CuffSert::Abort.new('badness')] }

    it { should eq(events) }
  end

  context 'given an exception' do
    let(:stream) { Rx::Observable.raise_error(CuffSert::CuffSertError.new('badness')) }

    it do
      expect { subject }.to raise_exception(SystemExit)
      expect(renderer.rendered).to contain_exactly(have_attributes(message: 'badness'))
    end
  end
end
