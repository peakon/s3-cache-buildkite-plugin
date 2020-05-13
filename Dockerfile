FROM node:14-alpine

WORKDIR /app

COPY package.json package-lock.json /app/

RUN npm install --no-audit --production

COPY lib /app/lib
COPY entrypoint.sh /app/lib/

ENV NODE_ENV production

ENTRYPOINT ["/app/lib/entrypoint.sh"]
