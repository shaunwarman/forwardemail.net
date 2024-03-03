# Use an official Node.js runtime as a parent image
FROM node:20

# Set the working directory in the container
WORKDIR /usr/src/app

# create cert / key / ca and dhparam
# set the path as WEB_SSL_* env vars

RUN npm install -g pnpm

# Copy package.json and package-lock.json (or yarn.lock) into the working directory
COPY package*.json ./

# Install any needed packages specified in package*.json
RUN pnpm i

# Copy the rest of your application's code into the working directory
COPY . .

RUN npm run build