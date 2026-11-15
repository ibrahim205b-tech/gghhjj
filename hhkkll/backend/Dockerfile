# HHKKLL question service. Secrets are passed at run time, never baked in:
#   docker run -e ANTHROPIC_API_KEY=... -e DAILY_BUDGET_USD=3 -p 8080:8080 -v hhkkll-data:/app/data hhkkll-backend
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
COPY test ./test
RUN npx tsc -p .

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production DATA_DIR=/app/data PORT=8080
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
VOLUME /app/data
EXPOSE 8080
CMD ["node", "dist/src/server.js"]
