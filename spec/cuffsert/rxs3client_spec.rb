require 'cuffsert/rxs3client'
require 'rx-rspec'
require 'spec_helpers'

describe CuffSert::RxS3Client do
  include_context 'templates'

  let(:s3_upload_prefix) { 's3://ze-bucket/ze/path' }
  let(:s3mock) { double(:s3mock) }
  let(:stack_uri) { URI.join('file:///', template_body.path) }

  describe '#upload' do
    subject { described_class.new(s3_upload_prefix, client: s3mock).upload(stack_uri) }

    let(:result_url) { subject[0] }
    let(:observable) { subject[1] }

    before do
      allow(s3mock).to receive(:put_object)
    end

    it 'returns the S3 URI of the newly uploaded object' do
      s3url = URI("#{s3_upload_prefix}/#{File.basename(template_body.path)}")
      expect(result_url).to eq(s3url)
    end

    it 'returns an observable which completes' do
      s3url = "#{s3_upload_prefix}/#{File.basename(template_body.path)}"
      expect(observable).to emit_exactly(CuffSert::Report.new(/#{s3url}/))
    end

    it 'uploads the referenced file to S3' do
      expect(observable).to complete
      expect(s3mock).to have_received(:put_object).with({
        body: template_json,
        bucket: 'ze-bucket',
        key: "ze/path/#{File.basename(template_body.path)}"
      })
    end

    context 'when upload prefix has no prefix' do
      let(:s3_upload_prefix) { 's3://ze-bucket/' }

      it 'constructs a well-formed S3 URI' do
        s3url = URI("#{s3_upload_prefix}#{File.basename(template_body.path)}")
        expect(result_url).to eq(s3url)
      end
    end

    context 'when upload fails' do
      before do
        allow(s3mock).to receive(:put_object).and_raise(RuntimeError.new)
      end

      it 'the observable errors' do
        expect(observable.ignore_elements).to emit_error(RuntimeError, /.*/)
      end
    end
  end
end
