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
      it { should match(/resource2_id/) }
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
end
