FROM alpine:3.20
WORKDIR /app
RUN echo "stockops app placeholder" > /app/README.txt
CMD ["sh","-c","echo running stockops placeholder; sleep infinity"]
