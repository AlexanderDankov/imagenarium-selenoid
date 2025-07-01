FROM aerokube/selenoid-ui:1.10.11 AS build

FROM alpine AS final
RUN apk add --no-cache bash curl jq
COPY --from=build /selenoid-ui /
ENTRYPOINT ["/selenoid-ui"]