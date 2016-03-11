FROM nginx:1.9
MAINTAINER Andrey Larin <lestex@gmail.com>

RUN rm /usr/share/nginx/html/*

COPY configs/nginx.conf /etc/nginx/nginx.conf
COPY configs/default.conf /etc/nginx/conf.d/default.conf

COPY certs/productionexample.crt /etc/ssl/certs/productionexample.crt
COPY certs/productionexample.key /etc/ssl/certs/productionexample.key
COPY certs/dhparam.pem /etc/ssl/provate/dhparam.pem

COPY docker-entrypoint /
RUN chmod +x /docker-entrupoint
ENTRYPOINT ["/docker-entrypoint"]

CMD ["nginx", "-g", "daemon off"]