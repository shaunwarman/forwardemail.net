FROM node:latest AS builder

WORKDIR /app

RUN npm install -g pnpm

COPY . .

RUN pnpm i && npm run build

## build everything in the first stage and then
## leverage .dockerignore and 2nd stage to remove files
## from the built image that we don't want included
FROM node:slim

WORKDIR /app

COPY --from=builder /app /app
