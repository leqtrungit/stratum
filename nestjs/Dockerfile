# =============================================================================
# Stage 1: Build
# =============================================================================
FROM node:20-alpine AS builder

# Install pnpm
RUN npm install -g pnpm

WORKDIR /app

# Copy lockfile and package.json
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source
COPY . .

# Build the app
RUN pnpm run build

# =============================================================================
# Stage 2: Production
# =============================================================================
FROM node:20-alpine AS production

# Install pnpm (needed for some run scripts if using pnpm start)
RUN npm install -g pnpm

WORKDIR /app

# Copy production dependencies only
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

# Copy built assets from builder
COPY --from=builder /app/dist ./dist

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "dist/main.js"]
