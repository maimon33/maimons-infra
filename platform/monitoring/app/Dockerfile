FROM python:3.13.7-alpine3.22

RUN addgroup -S monitor && \
    adduser -S -G monitor monitor && \
    install -d -o monitor -g monitor /data

COPY app/app.py /app/app.py

USER monitor
EXPOSE 3000
VOLUME ["/data"]

ENTRYPOINT ["python", "/app/app.py"]
