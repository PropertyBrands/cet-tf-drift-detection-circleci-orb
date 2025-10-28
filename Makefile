.PHONY: help build generate-wrapper pack validate clean

## Show this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

## Build the orb (generate wrapper + pack)
build: generate-wrapper pack
	@echo ""
	@echo "Orb built successfully!"
	@echo "Output: orb.yml"

## Generate the Python wrapper script from validate_drift.py
generate-wrapper:
	@./scripts/generate_python_wrapper.sh

## Pack the orb from src/ into orb.yml
pack:
	@echo "Packing orb..."
	@circleci orb pack src > orb.yml

## Validate the packed orb
validate: build
	@echo ""
	@echo "Validating orb..."
	@circleci orb validate orb.yml

## Clean generated files
clean:
	@rm -f orb.yml
	@echo "Cleaned generated orb.yml"

