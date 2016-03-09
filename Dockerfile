FROM jruby:9.0-jdk

RUN echo 'gem: --no-rdoc --no-ri' >> /.gemrc

ENV GEM_HOME /usr/local/bundle
ENV PATH $GEM_HOME/bin:$PATH
RUN gem install bundler \
  && bundle config --global path "$GEM_HOME" \
  && bundle config --global bin "$GEM_HOME/bin"

# don't create ".bundle" in all our apps
ENV BUNDLE_APP_CONFIG $GEM_HOME

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Install kubernetes-secret-env
ENV KUBERNETES_SECRET_ENV_VERSION=0.0.1
RUN \
  mkdir -p /etc/secret-volume && \
  cd /usr/local/bin && \
  curl -fLO https://github.com/newsdev/kubernetes-secret-env/releases/download/$KUBERNETES_SECRET_ENV_VERSION/kubernetes-secret-env && \
  chmod +x kubernetes-secret-env


# these didn't work as ONBUILD, strangely. Idk why. -BJBM
ADD src/Gemfile /usr/src/app/
ADD src/Gemfile.lock /usr/src/app/
RUN bundle install --system
ADD src/ /usr/src/app
