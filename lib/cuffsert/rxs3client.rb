require 'aws-sdk-s3'
require 'rx'

module CuffSert
  class RxS3Client
    def initialize(cli_args, client: nil)
      @bucket, @path_prefix = split_prefix(cli_args[:s3_upload_prefix])
      initargs = {retry_limit: 8}
      initargs[:region] = cli_args[:aws_region] if cli_args[:aws_region]
      @client = client || Aws::S3::Client.new(initargs)
    end

    def upload(stack_uri)
      file = stack_uri.to_s.sub(/^file:\/+/, '/')
      name = File.basename(file)
      s3_uri = "s3://#{@bucket}/#{@path_prefix}#{name}"
      observable = Rx::Observable.create do |observer|
        body = open(file).read
        begin
          observer.on_next(Report.new("Uploading template to #{s3_uri}"))
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
      [URI(s3_uri), observable]
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
