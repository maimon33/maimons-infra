FROM python:3.13.7-alpine3.22

RUN addgroup -S monitor && adduser -S -G monitor monitor

COPY app.py /app/app.py

USER monitor
EXPOSE 3000

ENTRYPOINT ["python", "/app/app.py"]
