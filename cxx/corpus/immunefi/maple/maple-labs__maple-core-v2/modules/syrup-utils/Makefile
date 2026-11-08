build:
	@scripts/build.sh -p default

coverage:
	@scripts/coverage.sh

test:
	@scripts/test.sh -p default

deploy:
	@scripts/deploy.sh

validate:
	@FOUNDRY_PROFILE=production forge script Validate$(step)
