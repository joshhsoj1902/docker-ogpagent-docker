build:
	docker build -t joshhsoj1902/docker-ogpagent-docker .

test:
	docker-compose -f docker-compose.test.yml up -d
	sleep 2
	docker-compose -f docker-compose.test.yml exec agent "/tests/start-server.sh"

.PHONY: build
