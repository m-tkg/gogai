FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY tsconfig.json ./

RUN npm install -D typescript && npx tsc && npm uninstall typescript

RUN mkdir -p /app/data

EXPOSE 3040

CMD ["node", "dist/index.js"]
