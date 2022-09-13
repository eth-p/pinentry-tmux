PREFIX ?= /usr/local

install:
	cp "pinentry-tmux.sh" "${PREFIX}/bin/pinentry-tmux"
	chmod 755 "${PREFIX}/bin/pinentry-tmux"
	chown "$$(id -u):$$(id -g)" "${PREFIX}/bin/pinentry-tmux"
