build:
	docker build -t joshhsoj1902/docker-ogpagent-docker .


### TESTS ###
test: build test-setup

test-setup:
	docker-compose up -d
	sleep 1
	docker-compose exec agent "/tests/start-server.sh"

# test-running:
# 	# https://github.com/kadwanev/retry
# 	@retry -v -s 5 -t 30 'docker exec $(docker ps -f name=game -q) "./docker-health.sh"'


.PHONY: build
