FROM ghcr.io/dependabot/dependabot-updater-core

USER root

RUN mkdir -p /resolved_dependencies
RUN chown dependabot /resolved_dependencies

RUN apt update && \
    apt install python3 build-essential zlib1g-dev libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev libncurses-dev tk-dev -y

USER dependabot

COPY --chown=dependabot:dependabot waf $DEPENDABOT_HOME/waf
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater