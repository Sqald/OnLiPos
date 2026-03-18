ARG NGINX_DOCKER_VERSION=alpine-slim
FROM nginx:${NGINX_DOCKER_VERSION}
COPY ./nginx-rails.conf /etc/nginx/conf.d/default.conf
COPY ./99-ssl.sh /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/*
EXPOSE 80
EXPOSE 443