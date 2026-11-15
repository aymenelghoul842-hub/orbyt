# Builds the Flutter web app and serves it together with the Node server.
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /app
COPY client/ client/
# Empty SERVER_URL = same origin as the page (the Node server serves the app)
RUN cd client && flutter pub get && flutter build web --release --dart-define=SERVER_URL=

FROM node:20-alpine
ENV NODE_ENV=production PORT=3000 DATA_DIR=/data
WORKDIR /app
COPY server/package.json server/package-lock.json* server/
RUN cd server && (npm ci --omit=dev || npm install --omit=dev)
COPY server/ server/
COPY --from=web /app/client/build/web client/build/web
RUN mkdir -p /data && chown -R node:node /data /app
USER node
VOLUME /data
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=4s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1
CMD ["node", "server/index.js"]
