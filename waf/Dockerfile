FROM ghcr.io/dependabot/dependabot-updater-core

USER root

RUN mkdir -p /resolved_dependencies
RUN chown dependabot /resolved_dependencies

USER dependabot

COPY --chown=dependabot:dependabot waf $DEPENDABOT_HOME/waf
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater