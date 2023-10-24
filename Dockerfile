# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.18 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG VERSION
ADD https://github.com/sct/overseerr.git#v$VERSION ./

# apply available patches
RUN apk add --no-cache patch
COPY patches ./
RUN find ./ -name "*.patch" -print0 | sort -z | xargs -t -0 -n1 patch -p1 -i

# build stage ==================================================================
FROM base AS build-backend

# dependencies
RUN apk add --no-cache build-base python3 nodejs-current && corepack enable

# node_modules
COPY --from=source /src/package.json /src/yarn.lock /src/tsconfig.json ./
ENV NEXT_TELEMETRY_DISABLED=1 CYPRESS_INSTALL_BINARY=0 HUSKY=0
RUN yarn global add yarn-deduplicate && yarn-deduplicate yarn.lock && \
    yarn install --frozen-lockfile --network-timeout 120000

# build app
COPY --from=source /src/next.config.js /src/next-env.d.ts /src/babel.config.js \
                   /src/postcss.config.js /src/tailwind.config.js ./
COPY --from=source /src/public ./public
COPY --from=source /src/server ./server
COPY --from=source /src/src ./src
RUN yarn build

# cleanup (very polluted app...)
RUN yarn install --production --ignore-scripts --prefer-offline && \
    rm -rf ./.next/cache && \
    rm -rf ./node_modules/@next/swc-linux-arm64-gnu && \
    find ./ -type f \( \
        -iname "*.cmd" -o -iname "*.bat" -o \
        -iname "*.map" -o -iname "*.md" -o \
        -iname "*.ts" -o -iname "*.git*" -o \
        -iname "Makefile" -o -iname "AUTHORS*" -o \
        -iname "LICENSE*" -o -iname "CONTRIBUTING*" -o \
        -iname "CHANGELOG*" -o -iname "README*" \
    \) -delete && \
    find ./ -type d -iname ".github" | xargs rm -rf && \
    find ./ -iname "node-gyp*" | xargs rm -rf && \
    find ./node_modules/ace-builds -type d \( \
        -iname "src" -o -iname "src-min" -o -iname "src-noconflict" \
    \) | xargs rm -rf

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
ENV CONFIG_DIRECTORY=/config
WORKDIR /config
VOLUME /config
EXPOSE 5055

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay nodejs-current curl

# copy files
COPY --from=source /src/package.json /src/overseerr-api.yml /app/
COPY --from=build-backend /src/node_modules /app/node_modules
COPY --from=build-backend /src/public /app/public
COPY --from=build-backend /src/dist /app/dist
COPY --from=build-backend /src/.next /app/.next
COPY ./rootfs/. /

# run using s6-overlay
ENTRYPOINT ["/init"]
