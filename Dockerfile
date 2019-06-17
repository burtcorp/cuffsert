FROM alpine:3.8 AS buildenv

RUN apk --no-cache add ruby ruby-bundler ruby-dev gcc make musl-dev
RUN echo 'gem: --no-rdoc --no-ri' > ~/.gemrc && mkdir /cuffsert
COPY ./Gemfile ./Gemfile.lock ./cuffsert.gemspec /cuffsert/
COPY ./bin /cuffsert/bin
COPY ./lib /cuffsert/lib

WORKDIR /cuffsert

RUN bundle install --deployment --without development --path .bundle/vendor --binstubs .bundle/bin --jobs 2

FROM alpine:3.8

RUN apk --no-cache add ruby ruby-bundler ruby-json ruby-webrick

COPY --from=buildenv /cuffsert/.bundle /cuffsert/.bundle
COPY ./Gemfile ./Gemfile.lock ./cuffsert.gemspec /cuffsert/
COPY ./bin /cuffsert/bin
COPY ./lib /cuffsert/lib

WORKDIR /cuffsert

ENTRYPOINT ["/usr/bin/bundle", "exec"]
