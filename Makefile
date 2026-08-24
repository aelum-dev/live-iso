.PHONY: build run run-1 run-2 run-3 run-4 run-5 clean help

# Default target
help:
	@echo "AestheticOS Docker Build Pipeline"
	@echo ""
	@echo "Usage:"
	@echo "  make build          Build the Docker image"
	@echo "  make run            Run full pipeline (steps 1-5)"
	@echo "  make run-1          Step 1: Download official packages"
	@echo "  make run-2          Step 2: Download AUR packages"
	@echo "  make run-3          Step 3: Build AUR packages"
	@echo "  make run-4          Step 4: Create offline repository"
	@echo "  make run-5          Step 5: Build ISO"
	@echo "  make clean          Remove build artifacts"
	@echo ""

build:
	docker compose -f docker/docker-compose.yml build

run:
	docker compose -f docker/docker-compose.yml run --rm builder

run-1:
	docker compose -f docker/docker-compose.yml run --rm builder 1

run-2:
	docker compose -f docker/docker-compose.yml run --rm builder 2

run-3:
	docker compose -f docker/docker-compose.yml run --rm builder 3

run-4:
	docker compose -f docker/docker-compose.yml run --rm builder 4

run-5:
	docker compose -f docker/docker-compose.yml run --rm builder 5

clean:
	rm -rf work/ output/*.iso
