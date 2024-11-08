# Étape 1 : Create container app
FROM node:20-alpine AS base
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install
COPY . .

# Étape 2 : Build for production
FROM base AS builder
RUN pnpm run build

# Étape 3 : Production
FROM node:20-alpine as production
WORKDIR /app
COPY --from=builder /app/public/ ./.next/standalone/public/
COPY --from=builder /app/.next/static/ ./.next/standalone/.next/static/
COPY --from=builder /app/.next/standalone/ ./.next/standalone/
CMD ["node", ".next/standalone/server.js"]

# Étape 2 bis : Development
FROM base as dev
EXPOSE 3000
CMD ["pnpm", "dev"]