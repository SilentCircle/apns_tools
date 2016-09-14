.PHONY: clean certs

all: clean certs

clean:
	@rm -rf CA

certs:
	@./fake_apple_certs.sh
