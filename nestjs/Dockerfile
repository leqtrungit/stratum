# =============================================================================
# Stage 0: Development (hot reload via mounted source)
# =============================================================================
FROM node:24-alpine AS development

RUN corepack enable

WORKDIR /app

COPY package.json pnpm-lock.yaml .npmrc ./

RUN pnpm install

ENV NODE_ENV=development
ENV PORT=3000

EXPOSE 3000

CMD ["pnpm", "run", "start:dev"]

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM node:24-alpine AS builder

# Enable corepack so pnpm version is sourced from packageManager in package.json
RUN corepack enable

WORKDIR /app

# Copy lockfile, package.json and .npmrc (needed for pnpm config before install)
COPY package.json pnpm-lock.yaml .npmrc ./

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source
COPY . .

# Build the app
RUN pnpm run build

# =============================================================================
# Stage 2: Production
# =============================================================================
FROM node:24-alpine AS production

WORKDIR /app

# Copy node_modules from builder (avoids reinstall + pnpm lifecycle script issues)
COPY --from=builder /app/node_modules ./node_modules

# Copy built assets and package.json
COPY --from=builder /app/dist ./dist
COPY package.json ./

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "dist/main.js"]
