require 'aws-sdk-s3'
require 'rx'

module CuffSert
  class RxS3Client
    def initialize(s3_upload_prefix, client: Aws::S3::Client.new)
      @bucket, @path_prefix = split_prefix(s3_upload_prefix)
      @client = client
    end

    def upload(stack_uri)
      file = stack_uri.to_s.sub(/^file:\/+/, '/')
      name = File.basename(file)
      observable = Rx::Observable.create do |observer|
        body = open(file).read
        begin
          @client.put_object({
            body: body,
            bucket: @bucket,
            key: "#{@path_prefix}#{name}"
          })
          observer.on_completed
        rescue => e
          observer.on_error(e)
        end
      end
      ["s3://#{@bucket}/#{@path_prefix}#{name}", observable]
    end

    private

    def split_prefix(s3_upload_prefix)
      m = s3_upload_prefix.match(/^s3:\/\/([-a-z0-9]+)(\/?.*)$/)
      bucket = m[1]
      prefix = m[2].sub(/^\//, '')
      prefix += '/' unless prefix.empty? || prefix.end_with?('/')
      [bucket, prefix]
    end
  end
end
